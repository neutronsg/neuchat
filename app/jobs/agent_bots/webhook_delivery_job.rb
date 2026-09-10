class AgentBots::WebhookDeliveryJob < ApplicationJob
  queue_as :high

  def perform(delivery_id)
    AgentBots::WebhookDeliveryService.deliver(delivery_id)
  end
end
