class BotSafetyReviews::Create
  def self.call(account, user, params)
    raise ArgumentError, 'Review account unavailable' unless BotSafetyClient.enabled?(account.id)

    settings = settings_for(params)
    key = params.fetch(:idempotency_key)
    raise ArgumentError, 'Invalid idempotency key' unless key.match?(/\A[a-zA-Z0-9_-]{8,100}\z/)

    existing = BotSafetyReviewRun.find_by(account: account, idempotency_key: key)
    if existing
      raise ArgumentError, 'Idempotency key has different settings' unless existing.settings == settings.deep_stringify_keys

      return existing
    end
    run = BotSafetyReviewRun.create!(account: account, user: user, idempotency_key: key, settings: settings,
                                     cutoff_at: Time.current, high_water_id: account.messages.maximum(:id) || 0)
    BotSafetyReviews::RunJob.perform_later(run.id)
    run
  end

  def self.settings_for(params)
    limit = Integer(params.fetch(:max_requests, 100))
    budget = Integer(params.fetch(:max_calls, 0))
    raise ArgumentError, 'AI review runs externally' if budget != 0 || params[:profile].present?
    raise ArgumentError, 'Invalid budget' unless limit.between?(1, 10_000) && budget.between?(0, limit)

    scope = params.fetch(:scope, 'all')
    raise ArgumentError, 'Invalid scope' unless %w[all blocked allowed issues].include?(scope)

    date_range(params).merge(scope: scope, max_requests: limit, max_calls: budget, profile: nil,
                             dry_run: true)
  end

  def self.date_range(params)
    zone = ActiveSupport::TimeZone[params.fetch(:timezone)]
    raise ArgumentError, 'Invalid timezone' unless zone

    first = Date.iso8601(params.fetch(:from_date))
    last = Date.iso8601(params.fetch(:to_date))
    raise ArgumentError, 'Invalid date range' if last < first

    day_after = last + 1
    { from: zone.local(first.year, first.month, first.day).utc.iso8601,
      to: zone.local(day_after.year, day_after.month, day_after.day).utc.iso8601, timezone: params[:timezone] }
  end
end
