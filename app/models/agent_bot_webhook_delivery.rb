class AgentBotWebhookDelivery < ApplicationRecord
  STATUSES = %w[pending processing retryable delivered dead_letter].freeze

  enum :status, STATUSES.index_by(&:itself), validate: true

  validates :delivery_key, :url, :webhook_type, :next_attempt_at, presence: true
  validates :attempts, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ready_for_delivery, lambda {
    where(status: %w[pending retryable])
      .where('next_attempt_at <= ?', Time.current)
  }

  scope :stale_processing, lambda {
    where(status: :processing)
      .where('locked_at <= ?', AgentBots::WebhookDeliveryService.stale_lock_cutoff)
  }
end
