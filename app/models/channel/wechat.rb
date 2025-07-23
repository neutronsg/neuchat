# == Schema Information
#
# Table name: channel_wechat
#
#  id               :bigint           not null, primary key
#  app_name         :string
#  app_secret       :string           not null
#  encoding_aes_key :string
#  token            :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :integer          not null
#  app_id           :string           not null
#
# Indexes
#
#  index_channel_wechat_on_account_id  (account_id)
#  index_channel_wechat_on_app_id      (app_id) UNIQUE
#
class Channel::Wechat < ApplicationRecord
  include Channelable

  self.table_name = 'channel_wechat'
  EDITABLE_ATTRS = [:app_id, :app_secret, :token, :encoding_aes_key].freeze

  before_validation :ensure_valid_app_credentials, on: :create
  validates :app_id, :app_secret, :token, presence: true
  validates :app_id, uniqueness: true
  before_save :setup_wechat_webhook

  def name
    'WeChat Mini Program'
  end

  def wechat_api_url
    'https://api.weixin.qq.com/cgi-bin'
  end

  def send_message_on_wechat(message)
    message_id = nil

    # Send text content if present
    message_id = send_message(message) if message.outgoing_content.present?

    # Send attachments if present
    if message.attachments.present?
      attachment_message_id = Wechat::SendAttachmentsService.new(message: message).perform
      # Use attachment message_id if text wasn't sent, otherwise keep text message_id
      message_id = attachment_message_id if message_id.nil?
    end

    message_id
  end

  def get_wechat_profile_image(openid)
    # Note: As of December 27, 2021, WeChat API no longer provides avatar/nickname information
    # This method is kept for backward compatibility but will return nil
    Rails.logger.info "WeChat no longer provides user avatar/nickname information (since Dec 2021)"
    nil
  end

  def get_wechat_user_info(openid)
    # Note: As of December 27, 2021, WeChat API no longer provides avatar/nickname information
    # This method is kept for backward compatibility but will return nil
    Rails.logger.info "WeChat no longer provides user avatar/nickname information (since Dec 2021)"
    nil
  end

  def get_access_token
    # WeChat access token with 2-hour expiry
    Rails.cache.fetch("wechat_access_token_#{app_id}", expires_in: 110.minutes) do
      response = HTTParty.get("#{wechat_api_url}/token",
                              query: {
                                grant_type: 'client_credential',
                                appid: app_id,
                                secret: app_secret
                              })

      if response.success? && response.parsed_response['access_token']
        response.parsed_response['access_token']
      else
        Rails.logger.error "WeChat access token error: #{response.parsed_response}"
        nil
      end
    end
  end

  def process_error(message, response)
    return unless response.parsed_response['errcode'] && response.parsed_response['errcode'] != 0

    # WeChat error codes: https://developers.weixin.qq.com/doc/offiaccount/Message_Management/Passive_user_reply_message.html
    message.external_error = "#{response.parsed_response['errcode']}: #{response.parsed_response['errmsg']}"
    message.status = :failed
    message.save!
  end

  def openid(message)
    message.conversation.contact_inbox.source_id
  end

  def msg_id(message)
    message.content_attributes['in_reply_to_external_id']
  end

  private

  def ensure_valid_app_credentials
    access_token = get_access_token
    return if access_token

    errors.add(:app_secret, 'invalid app credentials')
    return

    # Verify app name by getting basic info
    # response = HTTParty.get("#{wechat_api_url}/get_api_domain_ip",
    #   query: { access_token: access_token }
    # )

    # unless response.success? && response.parsed_response['errcode'] == 0
    #   errors.add(:app_id, 'invalid app configuration')
    # end
  end

  def setup_wechat_webhook
    # WeChat webhook is configured in WeChat Official Account/Mini Program backend
    # URL format: #{ENV.fetch('FRONTEND_URL', nil)}/webhooks/wechat/#{token}
    # This is manual configuration, not automatic like Telegram
    Rails.logger.info "WeChat webhook should be configured at: #{ENV.fetch('FRONTEND_URL', nil)}/webhooks/wechat/#{token}"
  end

  def send_message(message)
    access_token = get_access_token
    return nil unless access_token

    response = message_request(
      access_token,
      openid(message),
      message.outgoing_content
    )

    process_error(message, response)
    response.parsed_response['msgid'] if response.success?
  end

  def message_request(access_token, to_user, content)
    HTTParty.post("#{wechat_api_url}/message/custom/send",
                  query: { access_token: access_token },
                  headers: { 'Content-Type' => 'application/json; charset=utf-8' },
                  body: {
                    touser: to_user,
                    msgtype: 'text',
                    text: {
                      content: content
                    }
                  }.to_json)
  end
end
