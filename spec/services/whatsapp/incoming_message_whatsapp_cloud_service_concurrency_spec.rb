# rubocop:disable RSpec/AnyInstance -- Each worker loads independent records; inject channel/persistence failures across those instances.
require 'rails_helper'
require 'timeout'

RSpec.describe Whatsapp::IncomingMessageWhatsappCloudService do
  self.use_transactional_tests = false
  let!(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }

  after do
    account = channel.inbox.account
    channel.inbox.destroy!
    channel.destroy! if channel.persisted?
    account.contacts.destroy_all
    account.destroy!
  end

  def deliver(id, contacts: false)
    params = { entry: [{ changes: [{ value: {
      contacts: [{ profile: { name: 'Synthetic worker test' }, wa_id: '6590000001' }],
      messages: [{ id: id, from: '6590000001', timestamp: Time.now.to_i.to_s, type: 'text', text: { body: 'Test question' } }]
    } }] }] }.with_indifferent_access
    if contacts
      message = params[:entry].first[:changes].first[:value][:messages].first
      message[:type] = 'contacts'
      message[:contacts] = [{ name: { formatted_name: 'Synthetic A' } }, { name: { formatted_name: 'Synthetic B' } }]
    end
    Whatsapp::IncomingMessageWhatsappCloudService.new(inbox: channel.inbox, params: params).perform
  end

  def parallel(*actions)
    gate = Queue.new
    threads = actions.map do |action|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          gate.pop
          action.call
        end
      end
    end
    actions.size.times { gate << true }
    Timeout.timeout(20) { threads.each(&:value) }
  ensure
    threads&.each { |thread| thread.kill if thread.alive? }
    threads&.each(&:join)
  end

  it 'creates one message for concurrent duplicate incoming notifications' do
    parallel(-> { deliver('worker-duplicate') }, -> { deliver('worker-duplicate') })
    expect(channel.inbox.messages.where(source_id: 'worker-duplicate').count).to eq(1)
  end

  it 'deduplicates a multi-contact payload without dropping its individual contact records' do
    parallel(-> { deliver('worker-contacts', contacts: true) }, -> { deliver('worker-contacts', contacts: true) })
    expect(channel.inbox.messages.where(source_id: 'worker-contacts').count).to eq(2)
  end

  it 'creates only one active conversation for simultaneous first messages' do
    parallel(-> { deliver('worker-first-a') }, -> { deliver('worker-first-b') })
    expect(channel.inbox.conversations.count).to eq(1)
    expect(channel.inbox.messages.incoming.count).to eq(2)
  end

  it 'creates one resolved conversation without an empty extra chat for a blocked contact' do
    contact = create(:contact, account: channel.inbox.account, phone_number: '+6590000001', blocked: true)
    create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: '6590000001')

    deliver('worker-blocked')
    deliver('worker-blocked')

    expect(channel.inbox.conversations.count).to eq(1)
    conversation = channel.inbox.conversations.sole
    expect(conversation).to be_resolved
    expect(conversation.messages.incoming.pluck(:source_id)).to eq(['worker-blocked'])
  end

  it 'sends concurrent duplicate outgoing jobs only once' do
    deliver('worker-outgoing-input')
    message = create(:message, conversation: channel.inbox.conversations.first, message_type: :outgoing)
    calls = Queue.new
    allow_any_instance_of(Channel::Whatsapp).to receive(:send_message) do
      calls << true
      sleep 0.1
      'worker-sent-id'
    end
    parallel(*Array.new(2) { -> { SendReplyJob.perform_now(message.id) } })
    expect(calls.size).to eq(1)
    expect(message.reload.source_id).to eq('worker-sent-id')
  end

  it 'releases the sender and message locks after persistence failure and permits retry' do
    allow_any_instance_of(Message).to receive(:save!).and_raise(ActiveRecord::RecordInvalid)
    expect { deliver('worker-retry') }.to raise_error(ActiveRecord::RecordInvalid)
    allow_any_instance_of(Message).to receive(:save!).and_call_original
    parallel(-> { deliver('worker-retry') })
    expect(channel.inbox.messages.where(source_id: 'worker-retry').count).to eq(1)
  end

  it 'releases the sending lock after channel failure and permits retry' do
    deliver('worker-send-retry-input')
    message = create(:message, conversation: channel.inbox.conversations.first, message_type: :outgoing)
    allow_any_instance_of(Channel::Whatsapp).to receive(:send_message).and_raise(IOError)
    expect { SendReplyJob.perform_now(message.id) }.to raise_error(IOError)
    allow_any_instance_of(Channel::Whatsapp).to receive(:send_message).and_return('retried-send')
    parallel(-> { SendReplyJob.perform_now(message.id) })
    expect(message.reload.source_id).to eq('retried-send')
  end

  it 'starts one new conversation after the prior conversation closes' do
    deliver('worker-old')
    channel.inbox.conversations.first.update!(status: :resolved)
    parallel(-> { deliver('worker-new-a') }, -> { deliver('worker-new-b') })
    expect(channel.inbox.conversations.where.not(status: :resolved).count).to eq(1)
    expect(channel.inbox.conversations.count).to eq(2)
  end
end

# rubocop:enable RSpec/AnyInstance
