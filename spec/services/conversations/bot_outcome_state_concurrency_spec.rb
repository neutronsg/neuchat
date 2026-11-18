require 'rails_helper'
require 'timeout'

RSpec.describe Conversations::BotOutcomeState do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:bot) { create(:agent_bot, account: account) }

  before { create(:agent_bot_inbox, inbox: inbox, agent_bot: bot) }

  after { account.destroy! }

  def parallel(*actions)
    ready = Queue.new
    start = Queue.new
    workers = actions.map do |action|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          start.pop
          action.call
        end
      end
    end
    Timeout.timeout(15) do
      actions.size.times { ready.pop }
      actions.size.times { start << true }
      workers.each(&:value)
    end
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  def conversation
    create(:conversation, account: account, inbox: inbox)
  end

  def incoming(conv, text = 'Question')
    create(:message, conversation: conv, account: account, inbox: inbox, sender: conv.contact, message_type: :incoming, content: text)
  end

  def answer(conv, trigger, outcome: nil, command: nil)
    create(:message, conversation: conv, account: account, inbox: inbox, sender: bot, message_type: :outgoing,
                     content_attributes: { bot_outcome_protocol: 1, bot_outcome_authorized: true, bot_outcome: outcome,
                                           bot_trigger_message_id: trigger.id, bot_close_reason: command })
  end

  def solved
    { categories: [], enquiries: [{ id: 'q1', status: 'answered', evidence: 'current_reply' }],
      escalation: { stage: 'none', reason: 'none', destination: 'none', consentMessageId: 0 } }
  end

  it 'registers overlapping category sets in opposite order without deadlock or duplicate labels' do
    conversations = Array.new(2) { conversation }
    # Amplify the original opposite-lock-order race without blocking the fixed ordered writer.
    allow(Conversations::BotCategoryLabels).to receive(:ensure_label).and_wrap_original do |original, *args|
      result = original.call(*args)
      sleep 0.05
      result
    end
    orders = [['Sign-up/login', 'Learning related'], ['Learning related', 'Sign-up/login']]
    parallel(*conversations.each_with_index.map do |conv, i|
      -> { conv.reload.with_lock { Conversations::BotCategoryLabels.sync!(conv, orders[i]) } }
    end)
    expect(account.labels.pluck(:title)).to contain_exactly('sign-up-login', 'learning-related')
    conversations.each { |conv| expect(conv.reload.label_list).to contain_exactly('sign-up-login', 'learning-related') }
  end

  it 'serializes a late delivery failure with a closing reply and cannot restore solved' do
    conv = conversation
    faq = answer(conv, incoming(conv), outcome: solved)
    command = incoming(conv, 'End Conversation')
    parallel(
      -> { Message.find(faq.id).update!(status: :failed) },
      -> { answer(Conversation.find(conv.id), command, command: 'command') }
    )
    conv.reload.update!(status: :resolved)
    expect(conv.reload.bot_conversation_outcome.all_solved).to be(false)
  end

  it 'does not invalidate a newer independent answer when an older delivery fails concurrently' do
    conv = conversation
    old = answer(conv, incoming(conv), outcome: solved)
    new_input = incoming(conv)
    parallel(
      -> { Message.find(old.id).update!(status: :failed) },
      -> { answer(Conversation.find(conv.id), new_input, outcome: solved) }
    )
    expect(conv.reload.bot_conversation_outcome.all_solved).to be(true)
  end

  it 'keeps a carried historical answer dependent on a concurrent failed delivery receipt' do
    conv = conversation
    first = answer(conv, incoming(conv), outcome: solved)
    trigger = incoming(conv)
    snapshot = solved
    snapshot[:enquiries] = [{ id: 'q1', status: 'answered', evidence: 'previous_reply' },
                            { id: 'q2', status: 'answered', evidence: 'current_reply' }]
    parallel(
      -> { Message.find(first.id).update!(status: :failed) },
      -> { answer(Conversation.find(conv.id), trigger, outcome: snapshot) }
    )
    expect(conv.reload.bot_conversation_outcome.all_solved).to be(false)
  end

  [false, true].each do |verified|
    it "keeps simultaneous Widget messages in one new conversation (verified=#{verified})" do
      old = conversation
      old.update!(status: :resolved)
      contact_inbox = old.contact_inbox
      contact_inbox.update!(hmac_verified: verified)
      second_identity = verified ? create(:contact_inbox, contact: old.contact, inbox: inbox, hmac_verified: true) : contact_inbox
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with('OCA_BOT_REPORTS_ENABLED').and_return('true')
      allow(ENV).to receive(:[]).with('OCA_BOT_ACCOUNT_ID').and_return(account.id.to_s)
      requests = [contact_inbox, second_identity].map do |identity|
        Api::V1::Widget::MessagesController.new.tap do |controller|
          controller.instance_variable_set(:@contact, Contact.find(old.contact_id))
          controller.instance_variable_set(:@contact_inbox, identity)
          controller.instance_variable_set(:@conversation, Conversation.find(old.id))
          controller.params = ActionController::Parameters.new(message: { content: 'Question' })
          allow(controller).to receive_messages(inbox: inbox, auth_token_params: { inbox_id: inbox.id },
                                                conversation_params: { account: account, inbox: inbox, contact: old.contact,
                                                                       contact_inbox: identity })
        end
      end
      expect { parallel(*requests.map { |controller| -> { controller.create } }) }.to change { account.conversations.count }.by(1)
      fresh = account.conversations.order(:id).last
      expect(fresh.messages.incoming.count).to eq(2)
      expect(old.messages.incoming.count).to eq(0)
    end
  end
end
