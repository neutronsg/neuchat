# Loaded by real Sidekiq processes; never use against a shared/non-test database.
raise 'Local test only' unless ENV['RAILS_ENV'] == 'test' && ENV.fetch('POSTGRES_DATABASE').end_with?('_worker_rollout_test')

require 'uri'
raise 'Local PostgreSQL only' unless %w[localhost 127.0.0.1 ::1].include?(ENV.fetch('POSTGRES_HOST')) && ENV['DATABASE_URL'].nil?
raise 'Local Redis only' unless %w[localhost 127.0.0.1 ::1].include?(URI(ENV.fetch('REDIS_URL')).host)

require_relative '../../config/environment'
require 'webmock'
WebMock.enable!
WebMock.disable_net_connect!
require 'sidekiq'

module WorkerE2EChannel
  def send_message(_recipient, message)
    Sidekiq.redis { |redis| redis.incr("#{ENV.fetch('WORKER_E2E_QUEUE')}:sends:#{message.id}") }
    sleep 0.15
    "synthetic-sent-#{message.id}"
  end
end
Channel::Whatsapp.prepend(WorkerE2EChannel)

class WorkerE2EJob
  include Sidekiq::Job
  sidekiq_options retry: false

  def perform(action, args, token)
    prefix = ENV.fetch('WORKER_E2E_QUEUE')
    Sidekiq.redis { |redis| redis.set("#{prefix}:started:#{token}", Process.pid) }
    case action
    when 'incoming'
      incoming(args)
    when 'send'
      SendReplyJob.perform_now(args.fetch('id'))
    when 'idle'
      Conversations::BotIdleResolutionJob.perform_now
    when 'hold'
      sleep args.fetch('seconds')
    end
    Sidekiq.redis { |redis| redis.set("#{prefix}:done:#{token}", Process.pid) }
  rescue StandardError => e
    Sidekiq.redis { |redis| redis.set("#{prefix}:error:#{token}", e.class.name) }
    raise
  end

  def incoming(args)
    inbox = Inbox.find(args.fetch('inbox'))
    params = { entry: [{ changes: [{ value: {
      contacts: [{ profile: { name: 'Synthetic worker' }, wa_id: args.fetch('phone', '6590000002') }],
      messages: [{ id: args.fetch('id'), from: args.fetch('phone', '6590000002'), timestamp: Time.now.to_i.to_s,
                   type: 'text', text: { body: 'Synthetic question' } }]
    } }] }] }.with_indifferent_access
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: inbox, params: params).perform
  end
end
