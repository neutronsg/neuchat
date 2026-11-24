class BotSafetyReviews::RunJob < ApplicationJob
  queue_as :low

  def perform(id)
    @run = BotSafetyReviewRun.find(id)
    return unless claim

    select_items
    @run.items.order(:id).each do |item|
      @run.with_review_lease(@owner) { @run.update!(lease_until: 10.minutes.from_now) }
      BotSafetyReviews::ReviewItem.new(@run, item, @owner).call
    end
    incomplete = @run.items.where.not(status: 'completed').exists? || @run.summary.fetch('outside_budget').positive?
    @run.with_review_lease(@owner) { @run.update!(status: incomplete ? 'incomplete' : 'completed', lease_until: nil) }
  rescue BotSafetyReviewRun::LeaseLost
    nil
  rescue StandardError
    @run.with_review_lease(@owner) { @run.update!(status: 'failed', lease_until: nil) } if @owner
    # Never log message text, provider errors or credentials through ActiveJob retries.
  end

  private

  def claim
    @run.with_lock do
      next false unless @run.resumable?

      @owner = SecureRandom.uuid
      @run.update!(status: 'running', lease_until: 10.minutes.from_now, summary: @run.summary.merge('lease_owner' => @owner))
      true
    end
  end

  def select_items
    scope = source_scope
    matched = scope.count
    scope.order(:id).limit(@run.settings.fetch('max_requests')).each do |message|
      @run.items.find_or_create_by!(message_id: message.id) { |item| item.conversation_id = message.conversation_id }
    end
    @run.with_review_lease(@owner) do
      @run.update!(summary: @run.summary.merge(matched: matched, selected: @run.items.count, outside_budget: [matched - @run.items.count, 0].max))
    end
  end

  def source_scope
    messages = @run.account.messages
    bot_inboxes = AgentBotInbox.where(account_id: @run.account_id).select(:inbox_id)
    historical_inboxes = messages.where("content_attributes ->> 'bot_trigger_message_id' IS NOT NULL").select(:inbox_id)
    messages.where(inbox_id: bot_inboxes).or(messages.where(inbox_id: historical_inboxes)).incoming
            .where(private: false).where('id <= ?', @run.high_water_id).where('created_at <= ?', @run.cutoff_at)
            .where(created_at: Time.iso8601(@run.settings.fetch('from'))...Time.iso8601(@run.settings.fetch('to')))
  end
end
