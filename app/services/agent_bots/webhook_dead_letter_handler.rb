class AgentBots::WebhookDeadLetterHandler
  class << self
    def call(delivery)
      return unless delivery.webhook_type == 'agent_bot_webhook'

      message_id = delivery.payload[:id] || delivery.payload['id']
      message = Message.find_by(id: message_id)
      conversation = message&.conversation
      return unless conversation&.pending?

      conversation.open!
      enqueue_activity(conversation)
    rescue StandardError => e
      Rails.logger.error(
        "AgentBot webhook dead-letter fallback failed delivery_id=#{delivery.id} " \
        "error=#{e.class}:#{e.message}"
      )
    end

    private

    def enqueue_activity(conversation)
      content = I18n.t('conversations.activity.agent_bot.error_moved_to_open')
      Conversations::ActivityMessageJob.perform_later(
        conversation,
        {
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id,
          message_type: :activity,
          content: content
        }
      )
    end
  end
end
