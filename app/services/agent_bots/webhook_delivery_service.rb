require 'digest'

class AgentBots::WebhookDeliveryService
  MAX_ATTEMPTS = 8
  BASE_RETRY_DELAY = 1.second
  MAX_RETRY_DELAY = 5.minutes
  STALE_LOCK_AFTER = 2.minutes
  MAX_ERROR_LENGTH = 2_000
  DEFAULT_AGENT_BOT_TIMEOUT = 35
  MAX_AGENT_BOT_TIMEOUT = 120

  class << self
    def enqueue(url:, payload:, webhook_type: :agent_bot_webhook)
      delivery = find_or_create_delivery(url, payload, webhook_type)
      AgentBots::WebhookDeliveryJob.perform_later(delivery.id) unless terminal?(delivery)
      delivery
    end

    def deliver(delivery_id)
      delivery = claim(delivery_id)
      return unless delivery

      response = perform_request(delivery)
      mark_delivered(delivery, response)
    rescue StandardError => e
      handle_failure(delivery || AgentBotWebhookDelivery.find_by(id: delivery_id), e)
    end

    def stale_lock_cutoff
      STALE_LOCK_AFTER.ago
    end

    private

    def find_or_create_delivery(url, payload, webhook_type)
      delivery_key = build_delivery_key(url, payload, webhook_type)
      AgentBotWebhookDelivery.create!(
        delivery_key: delivery_key,
        url: url,
        payload: payload,
        webhook_type: webhook_type.to_s,
        status: :pending,
        next_attempt_at: Time.current
      )
    rescue ActiveRecord::RecordNotUnique
      AgentBotWebhookDelivery.find_by!(delivery_key: delivery_key)
    end

    def build_delivery_key(url, payload, webhook_type)
      source_id = payload[:id] || payload['id']
      material = if source_id.present?
                   [webhook_type, url, source_id].join(':')
                 else
                   [webhook_type, url, payload.to_json].join(':')
                 end
      Digest::SHA256.hexdigest(material)
    end

    def terminal?(delivery)
      delivery.delivered? || delivery.dead_letter?
    end

    def claim(delivery_id)
      delivery = AgentBotWebhookDelivery.find_by(id: delivery_id)
      return unless delivery

      claimed = false
      delivery.with_lock do
        if claimable?(delivery)
          delivery.update!(
            status: :processing,
            attempts: delivery.attempts + 1,
            locked_at: Time.current
          )
          claimed = true
        end
      end
      claimed ? delivery.reload : nil
    end

    def claimable?(delivery)
      return false if terminal?(delivery)
      return false if delivery.processing? && delivery.locked_at.present? && delivery.locked_at > stale_lock_cutoff
      return false if !delivery.processing? && delivery.next_attempt_at > Time.current

      true
    end

    def perform_request(delivery)
      RestClient::Request.execute(
        method: :post,
        url: delivery.url,
        payload: delivery.payload.to_json,
        headers: {
          'content_type' => :json,
          'accept' => :json,
          'X-NeuChat-Delivery-Key' => delivery.delivery_key
        },
        timeout: webhook_timeout
      )
    end

    def mark_delivered(delivery, response)
      delivery.update!(
        status: :delivered,
        delivered_at: Time.current,
        locked_at: nil,
        last_error: nil
      )
      Rails.logger.info(
        "AgentBot webhook delivered delivery_id=#{delivery.id} " \
        "attempts=#{delivery.attempts} http_status=#{response&.code}"
      )
    end

    def handle_failure(delivery, error)
      return unless delivery

      failure = persist_failure(delivery, error)
      return unless failure

      if failure[:dead_letter]
        AgentBots::WebhookDeadLetterHandler.call(delivery)
        Rails.logger.error(
          "AgentBot webhook dead-lettered delivery_id=#{delivery.id} " \
          "attempts=#{delivery.attempts} error=#{error.class}:#{error.message}"
        )
      else
        enqueue_retry(delivery, failure[:next_attempt_at])
        Rails.logger.warn(
          "AgentBot webhook retry scheduled delivery_id=#{delivery.id} " \
          "attempts=#{delivery.attempts} next_attempt_at=#{failure[:next_attempt_at]}"
        )
      end
    end

    def persist_failure(delivery, error)
      result = nil
      delivery.with_lock do
        unless terminal?(delivery)
          dead_letter = delivery.attempts >= MAX_ATTEMPTS
          next_attempt_at = Time.current + retry_delay(delivery.attempts) unless dead_letter
          delivery.update!(
            status: dead_letter ? :dead_letter : :retryable,
            next_attempt_at: next_attempt_at || Time.current,
            locked_at: nil,
            last_error: error.message.to_s.first(MAX_ERROR_LENGTH)
          )
          result = { dead_letter: dead_letter, next_attempt_at: next_attempt_at }
        end
      end
      result
    end

    def enqueue_retry(delivery, next_attempt_at)
      AgentBots::WebhookDeliveryJob.set(wait_until: next_attempt_at).perform_later(delivery.id)
    rescue StandardError => e
      Rails.logger.error(
        "AgentBot webhook retry enqueue failed delivery_id=#{delivery.id} " \
        "error=#{e.class}:#{e.message}"
      )
    end

    def retry_delay(attempts)
      [BASE_RETRY_DELAY * (2**[attempts - 1, 0].max), MAX_RETRY_DELAY].min
    end

    def webhook_timeout
      configured_timeout = Integer(
        ENV.fetch('AGENT_BOT_WEBHOOK_TIMEOUT', DEFAULT_AGENT_BOT_TIMEOUT),
        exception: false
      )
      return DEFAULT_AGENT_BOT_TIMEOUT unless configured_timeout&.positive?

      [configured_timeout, MAX_AGENT_BOT_TIMEOUT].min
    end
  end
end
