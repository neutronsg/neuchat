class BotSafetyReviews::ReviewItem
  TERMINAL = %w[completed insufficient_evidence execution_error].freeze
  ISSUES = %w[error timeout skipped unavailable indeterminate].freeze

  def initialize(run, item, owner)
    @run = run
    @item = item
    @owner = owner
  end

  def call
    return if TERMINAL.include?(@item.status)
    # A crashed in-flight call is unknown; never silently replay and charge again.
    return update('execution_error', error: 'previous_call_outcome_unknown') if @item.status == 'running'

    message = @run.account.messages.find_by(id: @item.message_id, conversation_id: @item.conversation_id)
    return update('insufficient_evidence', error: 'message_missing') unless message

    evidence = BotSafetyReviews::Evidence.call(@run, message)
    return update('insufficient_evidence', error: 'source_changed') unless save_manifest(evidence)
    return update('completed', outcome: 'outside_filter') unless selected?(evidence)

    review(evidence)
  rescue BotSafetyReviewRun::LeaseLost
    raise
  rescue StandardError
    update('execution_error', error: 'review_or_evidence_unavailable')
  end

  private

  def update(status, result)
    @run.with_review_lease(@owner) { @item.update!(status: status, result: result) }
  end

  def save_manifest(evidence)
    return false if @item.manifest.present? && @item.manifest != evidence[:manifest].deep_stringify_keys

    @run.with_review_lease(@owner) { @item.update!(manifest: evidence[:manifest]) }
  end

  def selected?(evidence)
    events = evidence[:audit]['events']
    blocked = enforced?(events, 'block')
    case @run.settings['scope']
    when 'blocked' then blocked
    when 'allowed' then !blocked && enforced?(events, 'allow')
    when 'issues' then evidence_issue?(evidence, events)
    else true
    end
  end

  def evidence_issue?(evidence, events)
    !BotSafetyReviews::Evidence.complete?(evidence) || events.empty? || events.any? { |e| ISSUES.include?(e['status']) }
  end

  def enforced?(events, status)
    events.any? { |e| e['enforced'] && e['status'] == status }
  end

  def review(evidence)
    unless BotSafetyReviews::Evidence.complete?(evidence)
      return update('insufficient_evidence', verdict: 'insufficient_evidence', reason: 'Audit evidence is incomplete')
    end
    return update('completed', outcome: 'export_only') if @run.settings['dry_run'] || @run.settings['profile'].blank?

    profile = @run.settings.fetch('profile')
    return update('insufficient_evidence', error: 'evidence_too_large') if evidence.to_json.bytesize > profile.fetch('maxInputBytes')
    return update('budget_exhausted', {}) unless reserve

    result = BotSafetyReviews::Client.call(@run.account_id, '/internal/safety/review', {
                                             profile: profile.fetch('name'), profileVersion: profile.fetch('version'),
                                             evidence: evidence, messageIds: evidence[:transcript].pluck(:id)
                                           }, post: true)
    update('completed', result)
  end

  def reserve
    @run.with_review_lease(@owner) do
      next false if @run.calls_reserved >= @run.settings.fetch('max_calls')

      @run.update!(calls_reserved: @run.calls_reserved + 1)
      @item.update!(status: 'running')
      true
    end
  end
end
