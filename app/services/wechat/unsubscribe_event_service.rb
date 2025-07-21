class Wechat::UnsubscribeEventService
  include ::Wechat::ParamHelpers
  pattr_initialize [:inbox!, :params!]

  def perform
    return unless params

    set_contact
    update_subscription_status
    create_unsubscribe_message
  end

  private

  def set_contact
    contact_inbox = @inbox.contact_inboxes.find_by(source_id: contact_identifier)
    return unless contact_inbox

    @contact_inbox = contact_inbox
    @contact = contact_inbox.contact
  end

  def update_subscription_status
    return unless @contact

    additional_attributes = @contact.additional_attributes || {}
    additional_attributes.merge!(
      subscription_status: 'unsubscribed',
      unsubscribed_at: Time.current
    )
    @contact.update!(additional_attributes: additional_attributes)
  end

  def create_unsubscribe_message
    return unless @contact_inbox

    # Find or create conversation
    @conversation = @contact_inbox.conversations.last || create_conversation

    # Create a system message for the unsubscribe event
    @conversation.messages.create!(
      account: @inbox.account,
      inbox: @inbox,
      message_type: :incoming,
      content: '用户已取消关注公众号', # "User unsubscribed from Official Account" in Chinese
      sender: @contact,
      content_attributes: {
        event_type: 'unsubscribe',
        wechat_openid: wechat_from_user
      }
    )
  end

  def create_conversation
    ::Conversation.create!(
      account: @inbox.account,
      inbox: @inbox,
      contact: @contact,
      contact_inbox: @contact_inbox,
      additional_attributes: conversation_additional_attributes
    )
  end

  def conversation_additional_attributes
    {
      wechat_event_type: 'unsubscribe',
      wechat_openid: wechat_from_user
    }
  end
end
