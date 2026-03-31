class Wechat::IncomingMessageService
  include ::FileTypeHelper
  include ::Wechat::ParamHelpers
  pattr_initialize [:inbox!, :params!]

  def perform
    set_contact
    update_contact_avatar
    set_conversation

    @message = @conversation.messages.build(
      content: wechat_message_content,
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      message_type: :incoming,
      sender: @contact,
      content_attributes: wechat_content_attributes,
      source_id: wechat_message_id.to_s
    )

    process_message_attachments
    @message.save!
  end

  private

  def set_contact
    contact_inbox = ::ContactInboxWithContactBuilder.new(
      source_id: contact_identifier,
      inbox: inbox,
      contact_attributes: contact_attributes
    ).perform

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact
  end

  def process_message_attachments
    attach_files if has_media_file?
    attach_location if has_location?
  end

  def update_contact_avatar
    # WeChat no longer provides avatar/nickname information since December 2021
    # Skip avatar update as the API no longer returns this data
    Rails.logger.debug 'Skipping WeChat avatar update - API no longer provides user profile data'
  end

  def conversation_params
    {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id,
      additional_attributes: conversation_additional_attributes
    }
  end

  def set_conversation
    # if lock to single conversation is disabled, create a new conversation when the previous one is resolved
    @conversation = if @inbox.lock_to_single_conversation
                      @contact_inbox.conversations.last
                    else
                      @contact_inbox.conversations.where.not(status: :resolved).last
                    end
    return if @conversation

    @conversation = ::Conversation.create!(conversation_params)
  end

  def contact_attributes
    {
      name: contact_name,
      additional_attributes: additional_attributes
    }
  end

  def additional_attributes
    {
      social_wechat_openid: contact_identifier,
      wechat_user_type: determine_user_type,
      wechat_app_id: inbox.channel.app_id,
      wechat_short_id: "#{contact_identifier[0..3]}...#{contact_identifier[-4..-1]}",
      wechat_openid_prefix: contact_identifier[0..7], # First 8 chars for grouping similar users
      wechat_conversation_started: Time.current.iso8601
    }
  end

  def conversation_additional_attributes
    {
      wechat_openid: wechat_from_user,
      wechat_app_id: inbox.channel.app_id,
      wechat_user_type: determine_user_type,
      channel_type: 'wechat_customer_service'
    }
  end

  def determine_user_type
    # Check if it's from Mini Program or Official Account based on OpenID format
    if contact_identifier.start_with?('o')
      'official_account'
    elsif contact_identifier.start_with?('w')
      'mini_program'
    else
      'unknown'
    end
  end

  def attach_files
    return unless has_media_file?

    if wechat_msg_type == 'image' && media_file_url
      # For images, WeChat provides direct PicUrl - download immediately like Telegram
      download_and_attach_from_url(media_file_url)
    elsif %w[voice video shortvideo].include?(wechat_msg_type) && media_id
      # For voice/video, download from WeChat API synchronously
      download_and_attach_from_api(media_id)
    end
  end

  def download_and_attach_from_url(url)
    attachment_file = Down.download(url)
    attach_file(attachment_file)
  rescue StandardError => e
    Rails.logger.error "WeChat media download error from URL: #{e.message}"
  end

  def download_and_attach_from_api(media_id)
    access_token = inbox.channel.get_access_token
    return unless access_token

    response = HTTParty.get("#{inbox.channel.wechat_api_url}/media/get",
                            query: {
                              access_token: access_token,
                              media_id: media_id
                            })

    if response.success? && response.headers['content-type']&.start_with?('image/', 'audio/', 'video/')
      create_temp_file_and_attach(response, media_id)
    else
      Rails.logger.error "WeChat media download failed: #{response.parsed_response}"
    end
  rescue StandardError => e
    Rails.logger.error "WeChat media download error from API: #{e.message}"
  end

  def create_temp_file_and_attach(response, media_id)
    content_type = response.headers['content-type']
    file_extension = determine_file_extension_from_content_type(content_type)
    filename = "wechat_#{wechat_msg_type}_#{media_id}#{file_extension}"

    # Create temporary file
    temp_file = Tempfile.new([filename, file_extension])
    temp_file.binmode
    temp_file.write(response.body)
    temp_file.rewind

    attach_file(temp_file, filename, content_type)
  ensure
    temp_file&.close
    temp_file&.unlink if temp_file&.path
  end

  def attach_file(file, filename = nil, content_type = nil)
    @message.attachments.new(
      account_id: @message.account_id,
      file_type: file_content_type,
      file: {
        io: file,
        filename: filename || file.original_filename || "wechat_#{wechat_msg_type}_#{media_id}",
        content_type: content_type || file.content_type || determine_content_type
      }
    )
  end

  def determine_file_extension_from_content_type(content_type)
    case content_type
    when %r{image/jpeg} then '.jpg'
    when %r{image/png} then '.png'
    when %r{image/gif} then '.gif'
    when %r{audio/mpeg} then '.mp3'
    when %r{audio/amr} then '.amr'
    when %r{video/mp4} then '.mp4'
    else
      case wechat_msg_type
      when 'image' then '.jpg'
      when 'voice' then '.amr'
      when 'video', 'shortvideo' then '.mp4'
      else '.bin'
      end
    end
  end

  def file_content_type
    case wechat_msg_type
    when 'image'
      :image
    when 'voice'
      :audio
    when 'video', 'shortvideo'
      :video
    else
      :file
    end
  end

  def determine_content_type
    case wechat_msg_type
    when 'image'
      'image/jpeg'
    when 'voice'
      'audio/amr'
    when 'video'
      'video/mp4'
    when 'shortvideo'
      'video/mp4'
    else
      'application/octet-stream'
    end
  end

  def attach_location
    return unless location_data

    @message.attachments.new(
      account_id: @message.account_id,
      file_type: :location,
      fallback_title: location_data[:label],
      coordinates_lat: location_data[:latitude],
      coordinates_long: location_data[:longitude]
    )
  end
end
