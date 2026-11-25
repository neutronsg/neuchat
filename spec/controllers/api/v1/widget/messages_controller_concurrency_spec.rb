require 'rails_helper'
require 'timeout'

RSpec.describe Api::V1::Widget::MessagesController, type: :controller do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:bot) { create(:agent_bot, account: account, bot_config: { idle_auto_resolve_enabled: true, idle_auto_resolve_after: 10 }) }
  let(:old) { create(:conversation, account: account, inbox: inbox) }

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('OCA_BOT_REPORTS_ENABLED').and_return('false')
    allow(ENV).to receive(:[]).with('OCA_BOT_ACCOUNT_ID').and_return(account.id.to_s)
    controller.instance_variable_set(:@contact, Contact.find(old.contact_id))
    controller.instance_variable_set(:@contact_inbox, old.contact_inbox)
    controller.instance_variable_set(:@conversation, Conversation.find(old.id))
    controller.params = ActionController::Parameters.new(message: { content: 'A new question' })
    allow(controller).to receive_messages(inbox: inbox, auth_token_params: { inbox_id: inbox.id },
                                          conversation_params: { account: account, inbox: inbox, contact: old.contact,
                                                                 contact_inbox: old.contact_inbox })
  end

  after { account.destroy! }

  def worker(&)
    Thread.new { ActiveRecord::Base.connection_pool.with_connection(&) }
  end

  def wait_for_lock(pid, thread)
    Timeout.timeout(8) do
      loop do
        return false unless thread.alive?
        if ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}") == 'Lock'
          return true
        end

        sleep 0.01
      end
    end
  end

  def finish_threads(release, *threads)
    release << true if release
    threads.compact.each { |thread| thread.kill if thread.alive? }
    threads.compact.each(&:join)
  end

  def arm_expired_idle
    trigger = create(:message, conversation: old, account: account, inbox: inbox, sender: old.contact, message_type: :incoming)
    create(:message, conversation: old, account: account, inbox: inbox, sender: bot, message_type: :outgoing,
                     content_attributes: { bot_idle_authorized: true, bot_idle_protocol: 1, bot_awaiting_user: true,
                                           bot_idle_notice: 'Idle closing notice', bot_trigger_message_id: trigger.id })
    old.reload.update!(bot_idle_deadline_at: 1.minute.ago)
  end

  it 'starts a new conversation if closure commits while Widget waits for the conversation lock' do
    closing = Queue.new
    release = Queue.new
    pid = Queue.new
    closer = worker do
      Conversation.find(old.id).with_lock do
        Conversation.find(old.id).update!(status: :resolved)
        closing << true
        release.pop
      end
    end
    Timeout.timeout(8) { closing.pop }
    writer = worker do |connection|
      pid << connection.select_value('SELECT pg_backend_pid()')
      controller.create
    end
    expect(wait_for_lock(Timeout.timeout(8) { pid.pop }, writer)).to be(true)
    release << true
    Timeout.timeout(8) { [closer, writer].each(&:value) }
    expect(old.reload).to be_resolved
    expect(old.messages.incoming.count).to eq(0)
    expect(account.conversations.count).to eq(2)
    expect(account.conversations.order(:id).last.messages.incoming.count).to eq(1)
  ensure
    finish_threads(release, closer, writer)
  end

  it 'holds the conversation lock through insertion so a waiting idle close rechecks and cancels' do
    arm_expired_idle
    selected = Queue.new
    release = Queue.new
    pid = Queue.new
    allow(controller).to receive(:set_conversation).and_wrap_original do |original|
      original.call
      selected << true
      release.pop
    end
    writer = worker { controller.create }
    Timeout.timeout(8) { selected.pop }
    closer = worker do |connection|
      pid << connection.select_value('SELECT pg_backend_pid()')
      Conversations::BotIdleResolutionJob.perform_now
    end
    expect(wait_for_lock(Timeout.timeout(8) { pid.pop }, closer)).to be(true)
    release << true
    Timeout.timeout(8) { [writer, closer].each(&:value) }
    expect(old.reload).to be_pending
    expect(old.bot_idle_deadline_at).to be_nil
    expect(old.messages.where(content: 'A new question').count).to eq(1)
    expect(old.messages.where(content: 'Idle closing notice').count).to eq(0)
    expect(account.conversations.count).to eq(1)
  ensure
    finish_threads(release, closer, writer)
  end

  it 'rolls back a new conversation if message persistence fails' do
    old.update!(status: :resolved)
    controller.params = ActionController::Parameters.new(message: { content: 'x' * 150_001 })
    expect { controller.create }.to raise_error(ActiveRecord::RecordInvalid)
    expect(old.reload).to be_resolved
    expect(account.conversations.count).to eq(1)
    expect(old.messages.incoming.count).to eq(0)
  end
end
