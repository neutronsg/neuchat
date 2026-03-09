require 'rails_helper'

RSpec.describe Integrations::Jsm::CloseTicketService do
  let(:account) { create(:account) }
  let(:hook) { create(:integrations_hook, :jsm, account: account) }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      status: :resolved,
      additional_attributes: {
        'jsm' => {
          'ticket_id' => '10001',
          'ticket_key' => 'SUP-123'
        }
      }
    )
  end

  before do
    hook
  end

  it 'closes the linked JSM ticket using the configured transition' do
    allow(HTTParty).to receive(:post).and_return(
      instance_double(HTTParty::Response, code: 204, parsed_response: nil)
    )

    described_class.new(conversation: conversation).perform

    expect(HTTParty).to have_received(:post).with(
      'https://example.atlassian.net/rest/api/3/issue/SUP-123/transitions',
      hash_including(
        headers: hash_including(
          'Accept' => 'application/json',
          'Content-Type' => 'application/json'
        ),
        body: { transition: { id: '31' } }.to_json
      )
    )
  end

  it 'does nothing when there is no linked JSM ticket' do
    conversation.update_column(:additional_attributes, {})
    allow(HTTParty).to receive(:post)

    described_class.new(conversation: conversation).perform

    expect(HTTParty).not_to have_received(:post)
  end
end
