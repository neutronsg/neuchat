class Conversations::ResolutionJob < ApplicationJob
  queue_as :low

  def perform(account:)
    # limiting the number of conversations to be resolved to avoid any performance issues
    resolvable_conversations = conversation_scope(account).limit(Limits::BULK_ACTIONS_LIMIT)
    resolvable_conversations.each do |conversation|
      conversation.with_lock do
        next if Conversations::BotIdleState.managed?(conversation)
        next unless legacy_scope(account).exists?(id: conversation.id)

        # send message from bot that conversation has been resolved
        # do this is account.auto_resolve_message is set
        ::MessageTemplates::Template::AutoResolve.new(conversation: conversation).perform if account.auto_resolve_message.present?
        conversation.add_labels(account.auto_resolve_label) if account.auto_resolve_label.present?
        conversation.update!(status: :resolved)
      end
    end
  end

  private

  def conversation_scope(account)
    managed_inboxes = account.inboxes.includes(:channel, agent_bot_inbox: :agent_bot).select do |inbox|
      Conversations::BotIdleState.enabled_for_inbox?(inbox)
    end
    # Exclude before applying the batch limit, so bot conversations cannot starve human work.
    managed_conversations = account.conversations.pending.where(inbox_id: managed_inboxes.map(&:id)).select(:id)
    legacy_scope(account).where.not(id: managed_conversations)
  end

  def legacy_scope(account)
    if account.auto_resolve_ignore_waiting
      account.conversations.resolvable_not_waiting(account.auto_resolve_after)
    else
      account.conversations.resolvable_all(account.auto_resolve_after)
    end
  end
end
