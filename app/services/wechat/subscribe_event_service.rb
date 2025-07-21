class Wechat::SubscribeEventService
  include ::Wechat::ParamHelpers
  pattr_initialize [:inbox!, :params!]

  def perform
    return unless params

    set_contact
    create_conversation
    send_welcome_message
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

  def contact_attributes
    {
      name: contact_name,
      additional_attributes: additional_contact_attributes
    }
  end

  def additional_contact_attributes
    {
      wechat_openid: wechat_from_user,
      subscription_status: 'subscribed',
      subscribed_at: Time.current
    }
  end

  def create_conversation
    @conversation = ::Conversation.create!(
      account: inbox.account,
      inbox: inbox,
      contact: @contact,
      contact_inbox: @contact_inbox,
      additional_attributes: conversation_additional_attributes
    )
  end

  def conversation_additional_attributes
    {
      wechat_event_type: 'subscribe',
      wechat_openid: wechat_from_user
    }
  end

  def send_welcome_message
    # Create a system message for the subscription event
    @conversation.messages.create!(
      account: inbox.account,
      inbox: inbox,
      message_type: :incoming,
      content: '用户已关注公众号', # "User subscribed to Official Account" in Chinese
      sender: @contact,
      content_attributes: {
        event_type: 'subscribe',
        wechat_openid: wechat_from_user
      }
    )
  end
end
