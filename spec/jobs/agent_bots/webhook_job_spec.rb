require 'rails_helper'

RSpec.describe AgentBots::WebhookJob do
  include ActiveJob::TestHelper

  subject(:job) { described_class.perform_later(url, payload, webhook_type) }

  let(:url) { 'https://test.com' }
  let(:payload) { { name: 'test' } }
  let(:webhook_type) { :agent_bot_webhook }

  it 'queues the job' do
    expect { job }.to have_enqueued_job(described_class)
      .with(url, payload, webhook_type)
      .on_queue('high')
  end

  it 'executes perform' do
    delivery = instance_double(AgentBotWebhookDelivery, id: 123)
    expect(AgentBots::WebhookDeliveryService).to receive(:enqueue)
      .with(url: url, payload: payload, webhook_type: webhook_type)
      .and_return(delivery)
    expect(AgentBots::WebhookDeliveryService).to receive(:deliver).with(123)
    perform_enqueued_jobs { job }
  end
end
