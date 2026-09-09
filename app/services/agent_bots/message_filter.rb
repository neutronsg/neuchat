module AgentBots::MessageFilter
  CUSTOMER_CONTENT_TYPES = %w[text input_text input_textarea incoming_email sticker voice_call].freeze
  SYSTEM_SENDER_TYPES = %w[AgentBot Captain::Assistant User System].freeze

  module_function

  def sendable?(message)
    return false unless message.incoming?
    return false if message.private?

    sender_type = message.sender_type.to_s
    return false if SYSTEM_SENDER_TYPES.include?(sender_type)
    return false unless sender_type == 'Contact'

    CUSTOMER_CONTENT_TYPES.include?(message.content_type.to_s)
  end
end
