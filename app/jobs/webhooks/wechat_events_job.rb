class Webhooks::WechatEventsJob < ApplicationJob
  queue_as :default

  def perform(params = {})
    return unless params[:token]

    channel = Channel::Wechat.find_by(token: params[:token])

    if channel_is_inactive?(channel)
      log_inactive_channel(channel, params)
      return
    end

    process_event_params(channel, params)
  end

  private

  def channel_is_inactive?(channel)
    return true if channel.blank?
    return true unless channel.account.active?

    false
  end

  def log_inactive_channel(channel, params)
    message = if channel&.id
                "Account #{channel.account.id} is not active for channel #{channel.id}"
              else
                "Channel not found for token: #{params[:token]}"
              end
    Rails.logger.warn("WeChat event discarded: #{message}")
  end

  def process_event_params(channel, params)
    # Handle both JSON and XML webhook data formats
    webhook_data = extract_webhook_data(params)
    return unless webhook_data

    # For WeChat Customer Service, we handle regular messages, not subscription events
    if webhook_data['MsgType'] == 'event' || webhook_data['msgtype'] == 'event'
      Rails.logger.info "WeChat Customer Service received event: #{webhook_data['Event'] || webhook_data['event']}"
      # Customer service doesn't handle subscription events - these are for Official Accounts
      return
    else
      # Handle customer service messages (text, image, etc.)
      Wechat::IncomingMessageService.new(inbox: channel.inbox, params: webhook_data).perform
    end
  end

  def extract_webhook_data(params)
    # Try JSON format first (new WeChat API)
    if params.key?('msgtype') || params.key?('MsgType')
      return params
    end

    # Fallback to XML format (legacy)
    if params[:xml].present?
      xml_data = Hash.from_xml(params[:xml])['xml']
      return xml_data if xml_data
    end

    # Direct params (already parsed)
    params.except(:token, :controller, :action)
  rescue => e
    Rails.logger.error "WeChat webhook data extraction error: #{e.message}"
    nil
  end
end
