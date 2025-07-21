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
    attach_media_file if has_media_file?
    attach_location if has_location?
  end

  def update_contact_avatar
    return if @contact.avatar.attached?

    avatar_url = inbox.channel.get_wechat_profile_image(contact_identifier)
    ::Avatar::AvatarFromUrlJob.perform_later(@contact, avatar_url) if avatar_url
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
    @conversation = @contact_inbox.conversations.first
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
      wechat_user_type: determine_user_type
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

  def attach_media_file
    return unless media_id

    # Download media file from WeChat servers
    Wechat::DownloadMediaJob.perform_later(@message, media_id, wechat_msg_type)
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
