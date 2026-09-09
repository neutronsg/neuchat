require 'rails_helper'

RSpec.describe AgentBots::WebhookDeliveryService do
  include ActiveJob::TestHelper

  let(:url) { 'https://neuai.test/webhooks/agent-bot' }
  let(:payload) do
    {
      id: 123,
      event: 'message_created',
      message_type: 'incoming',
      conversation: { id: 456 }
    }
  end

  before do
    clear_enqueued_jobs
  end

  it 'persists before enqueueing and de-duplicates the same source message' do
    first = described_class.enqueue(url: url, payload: payload)
    second = described_class.enqueue(url: url, payload: payload)

    expect(first.id).to eq(second.id)
    expect(AgentBotWebhookDelivery.count).to eq(1)
    expect(enqueued_jobs.map { |job| job[:job] }).to all(eq(AgentBots::WebhookDeliveryJob))
  end

  it 'marks a successful request delivered' do
    stub_request(:post, url).to_return(status: 200, body: '{}', headers: { content_type: 'application/json' })
    delivery = described_class.enqueue(url: url, payload: payload)

    described_class.deliver(delivery.id)

    expect(delivery.reload).to have_attributes(status: 'delivered', attempts: 1)
    expect(delivery.delivered_at).to be_present
  end

  it 'persists a retryable failure and schedules a retry' do
    stub_request(:post, url).to_raise(Errno::ECONNREFUSED)
    delivery = described_class.enqueue(url: url, payload: payload)
    clear_enqueued_jobs

    described_class.deliver(delivery.id)

    expect(delivery.reload).to have_attributes(status: 'retryable', attempts: 1)
    expect(delivery.last_error).to include('Connection refused')
    expect(enqueued_jobs).to include(
      hash_including(job: AgentBots::WebhookDeliveryJob, args: [delivery.id])
    )
  end

  it 'moves an exhausted delivery to the dead-letter state' do
    stub_request(:post, url).to_raise(Errno::ECONNREFUSED)
    delivery = described_class.enqueue(url: url, payload: payload)
    delivery.update!(status: :processing, attempts: described_class::MAX_ATTEMPTS, locked_at: Time.current)
    clear_enqueued_jobs

    described_class.deliver(delivery.id)

    expect(delivery.reload).to have_attributes(status: 'dead_letter', attempts: described_class::MAX_ATTEMPTS)
    expect(enqueued_jobs).to be_empty
  end
end
