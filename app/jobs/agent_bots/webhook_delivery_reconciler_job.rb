class AgentBots::WebhookDeliveryReconcilerJob < ApplicationJob
  queue_as :scheduled_jobs

  BATCH_SIZE = 100

  def perform
    AgentBotWebhookDelivery.ready_for_delivery.limit(BATCH_SIZE).find_each do |delivery|
      WebhookDeliveryJob.perform_later(delivery.id)
    end

    AgentBotWebhookDelivery.stale_processing.limit(BATCH_SIZE).find_each do |delivery|
      WebhookDeliveryJob.perform_later(delivery.id)
    end
  end
end
