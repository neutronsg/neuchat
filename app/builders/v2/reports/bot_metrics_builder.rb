class V2::Reports::BotMetricsBuilder
  include DateRangeHelper
  OCA_CONVERSATION_LIMIT = 50_000
  attr_reader :account, :params

  def initialize(account, params)
    @account = account
    @params = params
  end

  def metrics
    {
      conversation_count: conversation_count,
      message_count: bot_messages.count,
      resolution_rate: bot_resolution_rate.to_i,
      handoff_rate: bot_handoff_rate.to_i
    }
  end

  private

  def conversation_count
    return @conversation_count if defined?(@conversation_count)

    limit = params[:conversation_limit]
    count = limit ? bot_conversations.limit(limit + 1).count : bot_conversations.count
    raise BotReportLimitError, 'Reporting period too large' if limit && count > limit

    @conversation_count = count
  end

  def bot_activated_inbox_ids
    @bot_activated_inbox_ids ||= account.inboxes.filter(&:active_bot?).map(&:id)
  end

  def bot_conversations
    @bot_conversations ||= account.conversations.where(inbox_id: bot_activated_inbox_ids).where(created_at: range)
  end

  def bot_messages
    @bot_messages ||= account.messages.outgoing.where(conversation_id: bot_conversations.select(:id)).where(created_at: range)
  end

  def bot_resolutions_count
    account.reporting_events.joins(:conversation).select(:conversation_id).where(account_id: account.id, name: :conversation_bot_resolved,
                                                                                 created_at: range).distinct.count
  end

  def bot_handoffs_count
    account.reporting_events.joins(:conversation).select(:conversation_id).where(account_id: account.id, name: :conversation_bot_handoff,
                                                                                 created_at: range).distinct.count
  end

  def bot_resolution_rate
    return 0 if conversation_count.zero?

    bot_resolutions_count.to_f / conversation_count * 100
  end

  def bot_handoff_rate
    return 0 if conversation_count.zero?

    bot_handoffs_count.to_f / conversation_count * 100
  end
end
