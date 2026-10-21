class Conversations::BotIdleResolutionJob < ApplicationJob
  queue_as :low

  def perform
    Conversation.where(bot_idle_deadline_at: ..Time.current).order(:bot_idle_deadline_at).limit(Limits::BULK_ACTIONS_LIMIT).each do |conversation|
      resolve(conversation)
    end
  end

  private

  def resolve(conversation)
    conversation.with_lock do
      next unless conversation.bot_idle_deadline_at && conversation.bot_idle_deadline_at <= Time.current

      state = Conversations::BotIdleState.new(conversation)
      unless eligible?(conversation)
        state.clear
        next
      end

      create_notice(conversation)
      # Notification creation and state transition commit together. Delivery remains asynchronous.
      conversation.update!(status: :resolved)
    end
  end

  def create_notice(conversation)
    reply = conversation.messages.find(conversation.bot_idle_reply_id)
    public_notice = conversation.can_reply?
    content = if public_notice
                reply.content_attributes['bot_idle_notice']
              else
                I18n.t('conversations.activity.auto_resolve.not_sent_due_to_messaging_window')
              end
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: public_notice ? :template : :activity, content: content,
      content_attributes: { bot_close_reason: 'idle_timeout', bot_idle_source_reply_id: reply.id }
    )
  end

  def eligible?(conversation)
    return false unless Conversations::BotIdleState.managed?(conversation) && conversation.custom_attributes['ai_paused'] != true
    return false unless conversation.inbox.agent_bot_inbox.agent_bot_id == conversation.bot_idle_agent_bot_id

    reply = conversation.messages.find_by(id: conversation.bot_idle_reply_id)
    return false unless valid_reply?(reply)

    conversation.messages.where(private: false, message_type: [:incoming, :outgoing]).reorder(id: :desc).first&.id == reply.id
  end

  def valid_reply?(reply)
    reply && !reply.failed? && Conversations::BotIdleState.protocol_reply?(reply)
  end
end
