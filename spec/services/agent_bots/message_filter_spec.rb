require 'rails_helper'

RSpec.describe AgentBots::MessageFilter do
  subject(:sendable) { described_class.sendable?(message) }

  let(:message) { build(:message) }

  it 'accepts a public incoming customer text message' do
    expect(sendable).to be(true)
  end

  it 'rejects outgoing, private, non-contact, and system content' do
    expect(described_class.sendable?(build(:message, message_type: :outgoing))).to be(false)
    expect(described_class.sendable?(build(:message, private: true))).to be(false)
    expect(described_class.sendable?(build(:message, sender_type: 'User'))).to be(false)
    expect(described_class.sendable?(build(:message, content_type: :template))).to be(false)
    expect(described_class.sendable?(build(:message, content_type: :input_email))).to be(false)
  end
end
