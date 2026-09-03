class Webhooks::Trigger
  SUPPORTED_ERROR_HANDLE_EVENTS = %w[message_created message_updated].freeze
  DEFAULT_TIMEOUT = 5
  DEFAULT_AGENT_BOT_TIMEOUT = 35
  MAX_AGENT_BOT_TIMEOUT = 120

  def initialize(url, payload, webhook_type)
    @url = url
    @payload = payload
    @webhook_type = webhook_type
  end

  def self.execute(url, payload, webhook_type)
    new(url, payload, webhook_type).execute
  end

  def execute
    perform_request
  rescue StandardError => e
    handle_error(e)
    Rails.logger.warn "Exception: Invalid webhook URL #{@url} : #{e.message}"
  end

  private

  def perform_request
    RestClient::Request.execute(
      method: :post,
      url: @url,
      payload: @payload.to_json,
      headers: { content_type: :json, accept: :json },
      timeout: request_timeout
    )
  end

  def request_timeout
    return DEFAULT_TIMEOUT unless @webhook_type == :agent_bot_webhook

    configured_timeout = Integer(ENV.fetch('AGENT_BOT_WEBHOOK_TIMEOUT', DEFAULT_AGENT_BOT_TIMEOUT), exception: false)
    return DEFAULT_AGENT_BOT_TIMEOUT unless configured_timeout&.positive?

    [configured_timeout, MAX_AGENT_BOT_TIMEOUT].min
  end

  def handle_error(error)
    return unless should_handle_error?
    return unless message

    update_message_status(error)
  end

  def should_handle_error?
    @webhook_type == :api_inbox_webhook && SUPPORTED_ERROR_HANDLE_EVENTS.include?(@payload[:event])
  end

  def update_message_status(error)
    Messages::StatusUpdateService.new(message, 'failed', error.message).perform
  end

  def message
    return if message_id.blank?

    @message ||= Message.find_by(id: message_id)
  end

  def message_id
    @payload[:id]
  end
end
