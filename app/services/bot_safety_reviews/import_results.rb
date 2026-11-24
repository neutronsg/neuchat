require 'openssl'
require 'digest'

# Only signed Runner results create a new, immutable review batch. Source batches remain unchanged.
class BotSafetyReviews::ImportResults
  VERDICTS = %w[no_issue possible_false_positive possible_false_negative insufficient_evidence].freeze
  CALLED = %w[completed execution_error].freeze
  STATES = %w[completed execution_error insufficient_evidence budget_exhausted].freeze

  def self.call(account, user, content)
    new(account, user, content).call
  end

  def initialize(account, user, content)
    @account = account
    @user = user
    envelope = JSON.parse(content)
    raise ArgumentError unless envelope.is_a?(Hash)

    payload = envelope.fetch('payload')
    key = ENV.fetch('OCA_SAFETY_REVIEW_SIGNING_KEY', '')
    raise ArgumentError unless key.match?(/\A[0-9a-f]{64}\z/) && payload.is_a?(String)

    expected = OpenSSL::HMAC.hexdigest('SHA256', key, payload)
    raise ArgumentError unless ActiveSupport::SecurityUtils.secure_compare(expected, envelope.fetch('signature').to_s)

    @data = JSON.parse(payload)
    @digest = Digest::SHA256.hexdigest(payload)
    validate_header!
  rescue KeyError, TypeError
    raise ArgumentError, 'Invalid result envelope'
  end

  def call
    source = BotSafetyReviewRun.where(account: @account).find(@data.fetch('source_run_id'))
    source.with_lock do
      existing = BotSafetyReviewRun.find_by(account: @account, idempotency_key: execution_key)
      next existing if existing && existing.summary['result_digest'] == @digest
      raise ArgumentError, 'Conflicting result replay' if existing

      persist(source)
    end
  end

  private

  def execution_key
    "external-#{@data.fetch('execution_id')}"
  end

  def validate_header!
    raise ArgumentError unless @data.is_a?(Hash) && @data['source_run_id'].is_a?(Integer)

    validate_identity!
    validate_budget!
    validate_records!
    validate_reviewer!
  end

  def validate_identity!
    raise ArgumentError unless @data['format'] == 1 && @data['account_id'] == @account.id
    raise ArgumentError unless @data['environment'] == ENV.fetch('OCA_BOT_SAFETY_ENVIRONMENT', 'local')
    raise ArgumentError unless @data['execution_id'].is_a?(String) && @data['execution_id'].match?(/\A[a-zA-Z0-9_-]{1,70}\z/)
  end

  def validate_budget!
    raise ArgumentError unless @data['max_calls'].is_a?(Integer) && @data['max_calls'].between?(0, 100)
    raise ArgumentError unless @data['calls_attempted'].is_a?(Integer) && @data['calls_attempted'].between?(0, @data['max_calls'])
  end

  def validate_records!
    rows = @data['records']
    raise ArgumentError unless rows.is_a?(Array) && rows.length.between?(1, 10_000)
    raise ArgumentError unless rows.all? { |r| r.is_a?(Hash) && r['message_id'].is_a?(Integer) }
  end

  def validate_reviewer!
    reviewer = @data['reviewer']
    raise ArgumentError unless reviewer.is_a?(Hash) && reviewer['model'].is_a?(String) && reviewer['model'].length.between?(1, 200)
    raise ArgumentError unless reviewer['version'].is_a?(String) && reviewer['version'].match?(/\A[0-9a-f]{64}\z/)
  end

  def originals_for(source)
    ids = @data['records'].pluck('message_id')
    raise ArgumentError unless ids.uniq.length == ids.length

    originals = source.items.where(message_id: ids).index_by(&:message_id)
    raise ArgumentError unless originals.length == ids.length

    @data['records'].each { |row| validate_row!(row, originals.fetch(row['message_id'])) }
    calls = @data['records'].count { |row| CALLED.include?(row['status']) }
    raise ArgumentError unless calls == @data['calls_attempted']

    originals
  end

  def persist(source)
    originals = originals_for(source)
    run = new_run(source)
    @data['records'].each do |row|
      original = originals.fetch(row['message_id'])
      run.items.create!(message_id: original.message_id, conversation_id: original.conversation_id,
                        manifest: original.manifest, status: row['status'], result: row.fetch('result'))
    end
    run
  end

  def new_run(source)
    incomplete = @data['records'].any? { |r| r['status'] != 'completed' }
    BotSafetyReviewRun.create!(account: @account, user: @user, idempotency_key: execution_key,
                               status: incomplete ? 'incomplete' : 'completed', cutoff_at: source.cutoff_at, high_water_id: source.high_water_id,
                               calls_reserved: @data['calls_attempted'],
                               settings: source.settings.merge('source_run_id' => source.id, 'external_review' => true,
                                                               'profile' => @data['reviewer'], 'max_calls' => @data['max_calls']),
                               summary: { result_digest: @digest, execution_id: @data['execution_id'], selected: @data['records'].length,
                                          outside_budget: 0 })
  end

  def validate_row!(row, original)
    raise ArgumentError unless STATES.include?(row['status']) && row['manifest'] == original.manifest && row['result'].is_a?(Hash)
    return unless CALLED.include?(row['status'])

    raise ArgumentError unless export_source?(original)
    return unless row['status'] == 'completed'

    validate_verdict!(row['result']['result'], original)
  end

  def validate_verdict!(verdict, original)
    raise ArgumentError unless verdict.is_a?(Hash) && VERDICTS.include?(verdict['verdict'])
    raise ArgumentError unless verdict['reason'].is_a?(String) && verdict['reason'].length.between?(10, 2000)

    validate_references!(verdict, original)
  end

  def export_source?(original)
    original.status == 'completed' && original.result['outcome'] == 'export_only'
  end

  def allowed_id?(id, allowed)
    id.is_a?(Integer) && allowed.include?(id)
  end

  def validate_references!(verdict, original)
    ids = verdict['messageIds']
    allowed = original.manifest.fetch('messages').pluck('id')
    raise ArgumentError unless ids.is_a?(Array) && ids.length <= 30 && ids.all? { |id| allowed_id?(id, allowed) }
    raise ArgumentError if verdict['verdict'].start_with?('possible_') && ids.empty?
  end
end
