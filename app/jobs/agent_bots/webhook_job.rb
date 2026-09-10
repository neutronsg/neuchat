class AgentBots::WebhookJob < WebhookJob
  queue_as :high

  def perform(url, payload, webhook_type = :agent_bot_webhook)
    delivery = AgentBots::WebhookDeliveryService.enqueue(
      url: url,
      payload: payload,
      webhook_type: webhook_type
    )
    AgentBots::WebhookDeliveryService.deliver(delivery.id)
  end
end
