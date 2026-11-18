require 'rails_helper'

RSpec.describe Conversations::BotOutcomeState do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :pending) }
  let(:inbox) { create(:inbox, account: account) }
  let(:bot) { create(:agent_bot, account: account) }

  before { create(:agent_bot_inbox, inbox: inbox, agent_bot: bot) }

  def input
    create(:message, conversation: conversation, account: account, inbox: inbox, sender: conversation.contact, message_type: :incoming)
  end

  def outcome(status: 'answered', escalation: nil)
    { categories: ['Sign-up/login'], enquiries: [{ id: 'q1', status: status }],
      escalation: escalation || { stage: 'none', reason: 'none', destination: 'none', consentMessageId: 0 } }
  end

  def reply(trigger, data = outcome, sender: bot, authorized: true)
    create(:message, conversation: conversation, account: account, inbox: inbox, sender: sender, message_type: :outgoing,
                     content_attributes: { bot_outcome_protocol: 1, bot_outcome_authorized: authorized, bot_outcome: data,
                                           bot_trigger_message_id: trigger.id })
  end
  it 'persists FAQ outcomes and labels and settles only on closure' do
    conversation.update!(label_list: ['manual'])
    reply(input)
    state = conversation.reload.bot_conversation_outcome
    expect(state.all_solved).to be(true)
    expect(state.closed_at).to be_nil
    expect(conversation.label_list).to contain_exactly('manual', 'sign-up-login')
    conversation.update!(status: :resolved)
    expect(state.reload.closed_at).to be_present
  end

  it 'invalidates a previously solved snapshot on new input; stale replies cannot restore it' do
    old = input
    reply(old)
    input
    reply(old)
    expect(conversation.reload.bot_conversation_outcome.all_solved).to be(false)
  end

  it 'retains omitted unresolved enquiries across topic changes and restarts' do
    reply(input, outcome(status: 'unresolved'))
    conversation.reload
    data = outcome
    data[:enquiries] = [{ id: 'q2', status: 'answered' }]
    reply(input, data)
    expect(conversation.reload.bot_conversation_outcome.enquiries.size).to eq(2)
    expect(conversation.bot_conversation_outcome.all_solved).to be(false)
  end

  it 'records consent once and retains escalation when later enquiries are solved' do
    consent = input
    e = { stage: 'accepted', reason: 'requires_other_person', destination: 'company_admin', consentMessageId: consent.id }
    reply(consent, outcome(status: 'unresolved', escalation: e))
    reply(input, outcome(status: 'unresolved', escalation: e))
    state = conversation.reload.bot_conversation_outcome
    expect(state.escalations.size).to eq(1)
    expect(state.escalated_at).to be_present
    expect(state.all_solved).to be(false)
    reply(input, outcome(status: 'confirmed_solved'))
    expect(state.reload.all_solved).to be(true)
    expect(state.escalated_at).to be_present
  end

  it 'does not count an offer, refusal, or silence as accepted escalation' do
    %w[offered declined].each do |stage|
      reply(input,
            outcome(status: 'unresolved', escalation: { stage: stage, reason: 'requires_other_person', destination: 'hr', consentMessageId: 0 }))
      expect(conversation.reload.bot_conversation_outcome.escalated_at).to be_nil
    end
  end

  it 'rejects invalid or foreign consent atomically, preserving the unresolved state' do
    trigger = input
    expect do
      reply(trigger,
            outcome(escalation: { stage: 'accepted', reason: 'user_requested_support', destination: 'oca_support',
                                  consentMessageId: trigger.id + 999 }))
    end.to raise_error(ArgumentError)
    expect(conversation.reload.bot_conversation_outcome).to be_nil
  end

  it 'ignores forged metadata and ignores different bots' do
    trigger = input
    reply(trigger, outcome, authorized: false)
    reply(trigger, outcome, sender: create(:agent_bot, account: account))
    expect(conversation.reload.bot_conversation_outcome).to be_nil
  end

  it 'rolls back the reply if outcome persistence fails' do
    trigger = input
    allow(BotConversationOutcome).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap { |state| allow(state).to receive(:save!).and_raise(ActiveRecord::StatementInvalid) }
    end
    count = conversation.messages.count
    expect { reply(trigger) }.to raise_error(ActiveRecord::StatementInvalid)
    expect(conversation.messages.count).to eq(count)
  end

  it 'does not treat a failed model reply as solved' do
    sent = reply(input)
    sent.update!(status: :failed)
    expect(conversation.reload.bot_conversation_outcome.all_solved).to be(false)
  end

  it 'preserves FAQ resolution for the exact end command but not new questions' do
    reply(input)
    command = create(:message, conversation: conversation, account: account, inbox: inbox, sender: conversation.contact,
                               message_type: :incoming, content: 'End Conversation')
    create(:message, conversation: conversation, account: account, inbox: inbox, sender: bot, message_type: :outgoing,
                     content_attributes: { bot_outcome_protocol: 1, bot_outcome_authorized: true, bot_trigger_message_id: command.id,
                                           bot_close_reason: 'command' })
    conversation.reload.update!(status: :resolved)
    expect(conversation.bot_conversation_outcome.reload.all_solved).to be(true)
  end

  it 'cannot restore resolution across an unanswered input or a failed preceding answer' do
    [false, true].each do |failed|
      sent = reply(input)
      failed ? sent.update!(status: :failed) : input
      command = create(:message, conversation: conversation, account: account, inbox: inbox, sender: conversation.contact,
                                 message_type: :incoming, content: 'End Conversation')
      create(:message, conversation: conversation, account: account, inbox: inbox, sender: bot, message_type: :outgoing,
                       content_attributes: { bot_outcome_protocol: 1, bot_outcome_authorized: true, bot_trigger_message_id: command.id,
                                             bot_close_reason: 'command' })
      expect(conversation.reload.bot_conversation_outcome.all_solved).to be(false)
    end
  end

  it 'preserves each accepted contact route without counting multiple conversations' do
    consent = input
    %w[company_admin hr oca_support].each do |destination|
      reply(input, outcome(status: 'unresolved', escalation: { stage: 'accepted', reason: 'requires_other_person',
                                                               destination: destination, consentMessageId: consent.id }))
    end
    state = conversation.reload.bot_conversation_outcome
    expect(state.escalations.pluck('destination')).to eq(%w[company_admin hr oca_support])
    expect(BotConversationOutcome.where(conversation: conversation).count).to eq(1)
    expect(state.all_solved).to be(false)
  end

  it 'strips a human sender forged authorization marker in the actual message builder' do
    trigger = input
    human = create(:user, account: account)
    attrs = { bot_outcome_protocol: 1, bot_outcome_authorized: true, bot_outcome: outcome, bot_trigger_message_id: trigger.id }
    Messages::MessageBuilder.new(human, conversation,
                                 { content: 'A human reply', message_type: 'outgoing', content_attributes: attrs }).perform
    expect(conversation.reload.bot_conversation_outcome).to be_nil
  end

  def end_reply
    command = input
    command.update!(content: 'End Conversation')
    create(:message, conversation: conversation, account: account, inbox: inbox, sender: bot, message_type: :outgoing,
                     content_attributes: { bot_outcome_protocol: 1, bot_outcome_authorized: true, bot_trigger_message_id: command.id,
                                           bot_close_reason: 'command' })
  end

  it 'does not restore solved after a new question receives only a fixed error notice' do
    reply(input)
    reply(input, nil)
    conversation.reload
    end_reply
    expect(conversation.reload.bot_conversation_outcome.all_solved).to be(false)
  end

  it 'invalidates solved on a late failure of the answer underlying an end command, including after reload' do
    answer = reply(input)
    end_reply
    conversation.reload.update!(status: :resolved)
    Message.find(answer.id).update!(status: :failed)
    expect(conversation.reload.bot_conversation_outcome.all_solved).to be(false)
  end

  it 'retains delivery dependencies for omitted enquiries but replaces those answered again' do
    first = reply(input)
    second = outcome
    second[:enquiries] = [{ id: 'q2', status: 'answered' }]
    reply(input, second)
    first.update!(status: :failed)
    expect(conversation.reload.bot_conversation_outcome.all_solved).to be(false)
    data = outcome
    data[:enquiries][0][:evidence] = 'current_reply'
    reply(input, data)
    expect(conversation.reload.bot_conversation_outcome.all_solved).to be(true)
    first.update!(status: :sent)
    first.update!(status: :failed)
    expect(conversation.reload.bot_conversation_outcome.all_solved).to be(true)
  end

  it 'keeps the original reply dependency when a later full snapshot carries its answered status' do
    first = reply(input)
    data = outcome
    data[:enquiries] << { id: 'q2', status: 'answered' }
    reply(input, data)
    end_reply
    conversation.reload.update!(status: :resolved)
    Message.find(first.id).update!(status: :failed)
    expect(conversation.reload.bot_conversation_outcome.all_solved).to be(false)
  end

  it 'cannot erase a known failed dependency with a carried snapshot, but can explicitly reanswer' do
    first = reply(input)
    first.update!(status: :failed)
    data = outcome
    data[:enquiries] = [{ id: 'q1', status: 'answered', evidence: 'previous_reply' },
                        { id: 'q2', status: 'answered', evidence: 'current_reply' }]
    reply(input, data)
    expect(conversation.reload.bot_conversation_outcome.all_solved).to be(false)
    data[:enquiries][0][:evidence] = 'current_reply'
    data[:enquiries][1][:evidence] = 'previous_reply'
    reply(input, data)
    expect(conversation.reload.bot_conversation_outcome.all_solved).to be(true)
    first.update!(status: :sent)
    first.update!(status: :failed)
    expect(conversation.reload.bot_conversation_outcome.all_solved).to be(true)
  end

  it 'rejects carried new questions, changed statuses and unknown evidence atomically' do
    reply(input, outcome(status: 'unresolved'))
    [
      { id: 'q2', status: 'answered', evidence: 'previous_reply' },
      { id: 'q1', status: 'answered', evidence: 'previous_reply' },
      { id: 'q1', status: 'answered', evidence: 'invented' }
    ].each do |enquiry|
      data = outcome
      data[:enquiries] = [enquiry]
      trigger = input
      expect { reply(trigger, data) }.to raise_error(ArgumentError)
      expect(conversation.reload.bot_conversation_outcome.all_solved).to be(false)
    end
  end
end
