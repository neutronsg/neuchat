# Usage: RAILS_ENV=test POSTGRES_DATABASE=cag_worker_rollout_test ... bundle exec ruby spec/worker_e2e/run.rb
require 'securerandom'
require 'timeout'
require 'fileutils'
ENV['WORKER_E2E_QUEUE'] = "worker-e2e-#{SecureRandom.hex(6)}"
require_relative 'boot'
require 'factory_bot_rails'
require_relative '../../lib/sidekiq_worker_health'
FactoryBot.find_definitions if FactoryBot.factories.count.zero?

root = ENV.fetch('WORKER_E2E_ARTIFACTS', '/tmp/worker-e2e')
FileUtils.mkdir_p(root)
prefix = ENV.fetch('WORKER_E2E_QUEUE')
pids = []
results = {}
def wait_for
  Timeout.timeout(60) { sleep 0.05 until yield }
end

def redis_value(key)
  Sidekiq.redis { |redis| redis.get("#{ENV.fetch('WORKER_E2E_QUEUE')}:#{key}") }
end

def enqueue(action, args = {})
  token = SecureRandom.hex(8)
  WorkerE2EJob.set(queue: ENV.fetch('WORKER_E2E_QUEUE')).perform_async(action, args, token)
  token
end

def completed(tokens)
  wait_for do
    tokens.each { |token| raise redis_value("error:#{token}") if redis_value("error:#{token}") }
    tokens.all? { |token| redis_value("done:#{token}") }
  end
end

begin
  channel = FactoryBot.create(:channel_whatsapp, phone_number: '+6590000099', provider: 'whatsapp_cloud', sync_templates: false,
                                                 validate_provider_config: false)
  account = channel.inbox.account
  2.times do |i|
    pids << Process.spawn('bundle', 'exec', 'sidekiq', '-r', './spec/worker_e2e/boot.rb', '-q', prefix, '-c', '1', '-t', '10',
                          out: "#{root}/worker-#{i}.log", err: [:child, :out])
  end
  wait_for { pids.all? { |pid| SidekiqWorkerHealth.ready?(pid) } }
  results[:both_ready] = true
  holds = Array.new(2) { enqueue('hold', 'seconds' => 1) }
  completed(holds)
  raise 'Both processes must consume' unless holds.map { |t| redis_value("done:#{t}") }.uniq.size == 2

  completed(Array.new(2) { enqueue('incoming', 'inbox' => channel.inbox.id, 'id' => 'duplicate-e2e') })
  raise 'Duplicate incoming' unless channel.inbox.messages.where(source_id: 'duplicate-e2e').count == 1

  results[:incoming_dedup] = true
  completed(%w[first-a first-b].map { |id| enqueue('incoming', 'inbox' => channel.inbox.id, 'id' => id, 'phone' => '6590000003') })
  raise 'Duplicate conversations' unless channel.inbox.conversations.count == 2

  results[:conversation_creation] = true
  message = FactoryBot.create(:message, conversation: channel.inbox.conversations.first, message_type: :outgoing)
  completed(Array.new(2) { enqueue('send', 'id' => message.id) })
  raise 'Duplicate outgoing' unless redis_value("sends:#{message.id}") == '1'

  results[:outgoing_dedup] = true
  bot = FactoryBot.create(:agent_bot, account: account, bot_config: { idle_auto_resolve_enabled: true, idle_auto_resolve_after: 10 },
                                      idle_protocol_seen_at: Time.current)
  FactoryBot.create(:agent_bot_inbox, inbox: channel.inbox, agent_bot: bot)
  conv = channel.inbox.conversations.first
  conv.reload
  conv.inbox.reload
  conv.update!(status: :pending)
  trigger = conv.messages.incoming.last
  FactoryBot.create(:message, account: account, inbox: channel.inbox, conversation: conv, message_type: :outgoing,
                              sender: bot, content: 'Synthetic answer',
                              content_attributes: { bot_idle_authorized: true, bot_idle_protocol: 1, bot_idle_notice: 'Synthetic idle close',
                                                    bot_awaiting_user: true, bot_trigger_message_id: trigger.id })
  unless conv.reload.bot_idle_reply_id
    raise "Idle fixture not armed: #{conv.reload.attributes.slice('bot_idle_reply_id', 'bot_idle_agent_bot_id',
                                                                  'status')}"
  end

  conv.update!(bot_idle_deadline_at: 1.minute.ago)
  completed(Array.new(2) { enqueue('idle') })
  raise 'Duplicate idle close' unless conv.reload.messages.count { |m| m.content_attributes['bot_close_reason'] == 'idle_timeout' } == 1
  raise 'Idle close failed' unless conv.reload.resolved?

  results[:concurrent_idle_close] = true
  # Force incoming to wait behind a closing transaction, then recheck the state.
  other = channel.inbox.conversations.where.not(id: conv.id).first
  waiting = nil
  other.with_lock do
    other.update!(status: :resolved)
    waiting = enqueue('incoming', 'inbox' => channel.inbox.id, 'id' => 'after-close', 'phone' => '6590000003')
    wait_for { redis_value("started:#{waiting}") }
    owner = ActiveRecord::Base.connection.select_value('SELECT pg_backend_pid()').to_i
    wait_for do
      ActiveRecord::Base.connection.execute('SELECT pg_stat_clear_snapshot()')
      ActiveRecord::Base.connection.select_value("SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE #{owner} = ANY(pg_blocking_pids(pid)))")
    end
  end
  completed([waiting])
  raise 'Incoming reopened closed conversation' unless other.reload.resolved?
  raise 'Incoming entered closed conversation' if channel.inbox.messages.find_by!(source_id: 'after-close').conversation_id == other.id

  results[:incoming_waits_for_close_and_starts_new_chat] = true
  # A terminating old worker drains its in-flight task while the other keeps consuming.
  hold = enqueue('hold', 'seconds' => 3)
  wait_for { redis_value("started:#{hold}") }
  old_pid = redis_value("started:#{hold}").to_i
  Process.kill('TERM', old_pid)
  wait_for { !SidekiqWorkerHealth.ready?(old_pid) }
  live = enqueue('incoming', 'inbox' => channel.inbox.id, 'id' => 'during-drain')
  completed([live, hold])
  raise 'Quiet worker consumed new task' if redis_value("done:#{live}").to_i == old_pid

  Process.wait(old_pid)
  pids.delete(old_pid)
  results[:quiet_and_graceful_drain] = true
  results[:surviving_worker_continues] = true
  File.write("#{root}/result.json", JSON.pretty_generate(results))
  puts JSON.pretty_generate(results)
ensure
  pids.each do |pid|
    Process.kill('TERM', pid)
  rescue StandardError
    nil
  end
  # Signal every worker before waiting for any one of them.
  pids.each do |pid| # rubocop:disable Style/CombinableLoops
    Process.wait(pid)
  rescue StandardError
    nil
  end
  if channel
    channel.inbox.destroy!
    channel.destroy! if channel.persisted?
    account.contacts.destroy_all
    account.destroy!
  end
  # Only this run's private keys/queue; never flush the Redis database.
  Sidekiq.redis do |redis|
    keys = redis.call('KEYS', "#{prefix}:*")
    redis.del(*keys) unless keys.empty?
    redis.del("queue:#{prefix}")
    redis.srem('queues', prefix)
  end
end
