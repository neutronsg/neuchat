class AgentBotListener < BaseListener
  # The AgentBot contract starts from an actual customer message. Conversation
  # lifecycle events are internal Chatwoot events and must not start a model
  # turn or be retried as customer webhooks.
  def conversation_resolved(_event); end

  def conversation_opened(_event); end

  def message_created(event)
    message = extract_message_and_account(event)[0]
    inbox = message.inbox
    return unless AgentBots::MessageFilter.sendable?(message)
    return unless connected_agent_bot_exist?(inbox)

    method_name = __method__.to_s
    process_message_event(method_name, inbox.agent_bot, message, event)
  end

  # A message update is a transcript mutation, not a new customer turn. The
  # created event is the only event that enters the AgentBot conversation loop.
  def message_updated(_event); end

  # Widget lifecycle/system events are not customer messages and must not be
  # forwarded to an AgentBot endpoint.
  def webwidget_triggered(_event); end

  private

  def connected_agent_bot_exist?(inbox)
    return if inbox.agent_bot_inbox.blank?
    return unless inbox.agent_bot_inbox.active?

    true
  end

  def process_message_event(method_name, agent_bot, message, _event)
    # Only webhook bots are supported
    payload = message.webhook_data.merge(event: method_name)
    process_webhook_bot_event(agent_bot, payload)
  end

  def process_webhook_bot_event(agent_bot, payload)
    return if agent_bot.outgoing_url.blank?

    AgentBots::WebhookDeliveryService.enqueue(
      url: agent_bot.outgoing_url,
      payload: payload,
      webhook_type: :agent_bot_webhook
    )
  end
end
