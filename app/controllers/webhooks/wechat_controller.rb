class Webhooks::WechatController < ActionController::API
  before_action :verify_signature, only: [:process_payload]

  def process_payload
    # Handle WeChat webhook events (now supporting JSON format)
    webhook_params = parse_webhook_data
    Webhooks::WechatEventsJob.perform_later(webhook_params.merge(token: params[:token]))

    # Return appropriate response format
    if request.content_type&.include?('application/json')
      render json: { status: 'success' }
    else
      render xml: 'success'
    end
  end

  def verify
    # WeChat webhook URL verification
    # When setting up webhook, WeChat sends GET request with verification params
    if valid_verification_request?
      render plain: params[:echostr]
    else
      render plain: 'Invalid verification', status: :unauthorized
    end
  end

  private

  def parse_webhook_data
    if request.content_type&.include?('application/json')
      # Handle JSON format (new WeChat API)
      JSON.parse(request.body.read).with_indifferent_access
    else
      # Handle XML format (legacy WeChat API)
      xml_body = request.body.read
      if xml_body.present?
        Hash.from_xml(xml_body)['xml']&.with_indifferent_access || {}
      else
        params.to_unsafe_hash
      end
    end
  rescue JSON::ParserError, REXML::ParseException => e
    Rails.logger.error "WeChat webhook parse error: #{e.message}"
    params.to_unsafe_hash
  end

  def verify_signature
    return unless Rails.env.production?

    channel = Channel::Wechat.find_by(token: params[:token])
    return render(plain: 'Channel not found', status: :not_found) unless channel

    signature = params[:signature]
    timestamp = params[:timestamp]
    nonce = params[:nonce]

    unless valid_signature?(channel.token, signature, timestamp, nonce)
      render plain: 'Invalid signature', status: :unauthorized
    end
  end

  def valid_verification_request?
    params[:signature].present? &&
    params[:timestamp].present? &&
    params[:nonce].present? &&
    params[:echostr].present?
  end

  def valid_signature?(token, signature, timestamp, nonce)
    # WeChat signature verification
    # Sort token, timestamp, nonce and create SHA1 hash
    array = [token, timestamp, nonce].sort
    sha1_hash = Digest::SHA1.hexdigest(array.join)
    sha1_hash == signature
  end
end
