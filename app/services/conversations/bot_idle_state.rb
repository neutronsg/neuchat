# Protocol v1: only authenticated AgentBot replies may arm an idle deadline.
# waiting_since and human response metrics deliberately remain unchanged.
class Conversations::BotIdleState
  EMPTY_STATE = { bot_idle_deadline_at: nil, bot_idle_reply_id: nil, bot_idle_agent_bot_id: nil }.freeze

  def initialize(conversation)
    @conversation = conversation
  end

  def self.protocol_reply?(message)
    attributes = message.content_attributes || {}
    return false unless message.outgoing? && !message.private? && message.sender_type == 'AgentBot'

    attributes['bot_idle_authorized'] == true && attributes['bot_idle_protocol'] == 1 && valid_notice?(attributes['bot_idle_notice'])
  end

  def self.valid_notice?(notice)
    notice.is_a?(String) && notice.strip.present? && notice.length <= 12_000
  end

  def self.managed?(conversation)
    conversation.pending? && enabled_for_inbox?(conversation.inbox)
  end

  def self.enabled_for_inbox?(inbox)
    binding = inbox.agent_bot_inbox
    binding&.active? &&
      binding.agent_bot&.idle_auto_resolve? && binding.agent_bot.idle_protocol_seen_at.present?
  end

  def clear
    @conversation.update_columns(EMPTY_STATE) # rubocop:disable Rails/SkipsModelValidations
  end

  def on_message(message)
    return if message.private? || message.activity?

    clear if cancels_wait?(message)
    return unless eligible_reply?(message)

    binding = @conversation.inbox.agent_bot_inbox
    return unless matching_binding?(binding, message) && current_input?(message)

    # Bookkeeping inside the message transaction must not dispatch conversation callbacks.
    @conversation.update_columns( # rubocop:disable Rails/SkipsModelValidations
      bot_idle_deadline_at: message.created_at + binding.agent_bot.idle_auto_resolve_after.to_i.minutes,
      bot_idle_reply_id: message.id, bot_idle_agent_bot_id: message.sender_id
    )
  end

  private

  def cancels_wait?(message)
    @conversation.bot_idle_deadline_at && (message.incoming? || message.outgoing?)
  end

  def eligible_reply?(message)
    self.class.protocol_reply?(message) && !message.failed? && awaiting_user?(message) &&
      @conversation.pending? && @conversation.custom_attributes['ai_paused'] != true
  end

  def awaiting_user?(message)
    message.content_attributes['bot_awaiting_user'] == true && message.content_attributes['bot_close_reason'].blank?
  end

  def matching_binding?(binding, message)
    binding&.active? && binding.agent_bot_id == message.sender_id && binding.agent_bot&.idle_auto_resolve?
  end

  def current_input?(message)
    latest_input = @conversation.messages.incoming.where(private: false).reorder(id: :desc).first
    latest_input && latest_input.id == message.content_attributes['bot_trigger_message_id']
  end
end
