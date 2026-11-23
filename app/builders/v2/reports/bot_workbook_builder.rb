require 'caxlsx'

# Export the same reporting cohorts as the Bot page; pagination/reason filters
# affect the screen only. Unavailable metering must never become a zero cost.
class V2::Reports::BotWorkbookBuilder
  MISSING = 'Unavailable'.freeze
  TOKEN_COLUMNS = %w[calls failedCalls inputTokens outputTokens cacheReadTokens cacheWriteTokens cacheHitRate cacheCoverageCalls
                     usageMissingCalls].freeze
  COST_COLUMNS = %w[estimatedCostUsd estimatedGuardrailCostUsd estimatedCombinedCostUsd unpricedCalls guardrailCalls unpricedGuardrailCalls].freeze

  def initialize(account, params)
    @account = account
    @timezone = BotUsageReportClient.timezone(params)
    @from, @to = BotUsageReportClient.period(params)
    @params = { from: @from.to_i, to: @to.to_i, timezone: @timezone }
  end

  def filename
    dates = [@from, @to - 1.second].map { |time| time.in_time_zone(@timezone).to_date.iso8601 }.uniq
    "bot-report-#{dates.join('-to-')}.xlsx"
  end

  def to_stream
    load_data
    package = Axlsx::Package.new
    @book = package.workbook
    @header = @book.styles.add_style(b: true, bg_color: '16375B', fg_color: 'FFFFFF')
    summary_sheet
    table('Daily metrics', %w[Date Tracked_conversations Resolutions Escalations],
          @report[:days].map { |day| day.values_at(:day, :conversations, :resolutions, :escalations) })
    table('Enquiry categories', %w[Category Conversations], @report[:categories].sort)
    usage_sheet('Token usage', TOKEN_COLUMNS)
    usage_sheet('Cost estimates', COST_COLUMNS)
    conversation_sheet
    escalation_sheet
    package.to_stream
  end

  private

  def load_data
    builder = V2::Reports::BotOutcomesBuilder.new(@account, @params)
    @report = builder.build
    @rows = builder.export_rows
    @metrics = V2::Reports::BotMetricsBuilder.new(@account, since: @from.to_i.to_s, until: @to.to_i.to_s,
                                                            conversation_limit: V2::Reports::BotMetricsBuilder::OCA_CONVERSATION_LIMIT).metrics
    @usage = fetch_usage
  end

  def fetch_usage
    BotUsageReportClient.fetch(@account.id, @params)
  rescue BotReportLimitError
    raise
  rescue StandardError
    nil
  end

  def summary_sheet
    table('Summary', %w[Metric Value], summary_rows + pricing_rows + notes, widths: [42, 100])
  end

  def summary_rows
    [
      ['Period start (inclusive)', local_time(@from)], ['Period end (exclusive)', local_time(@to)],
      ['Timezone', @timezone], ['Generated at', local_time(Time.current)],
      ['Conversations', @metrics[:conversation_count]], ['Responses', @metrics[:message_count]],
      ['Tracked conversations (rate denominator)', @report[:conversation_count]],
      ['Resolution rate (%)', @report[:resolution_rate]], ['Escalation rate (%)', @report[:escalation_rate]],
      ['Tracking started at', local_time(@report[:tracking_started_at])]
    ]
  end

  def pricing_rows
    [['Usage status', @usage ? 'Available (see missing/unpriced call counts)' : MISSING]] +
      { 'Currency' => 'currency', 'Cost scope' => 'costScope', 'Storage' => 'storage', 'Price source' => 'priceSourceMode',
        'Prices last synced' => 'priceLastSyncedAt', 'Price sync stale' => 'priceSyncStale' }.map do |label, key|
        value = @usage && @usage[key]
        [label, key == 'priceLastSyncedAt' ? local_time(value) : value]
      end
  end

  def notes
    [
      ['Conversation/response totals',
       'Chats created in the period in currently bot-enabled inboxes; outgoing messages in the period for those chats.'],
      ['Outcome cohort', 'Chats first handled in the selected period. Categories and outcomes reflect their current tracked state.'],
      ['Resolution rate', 'Closed chats with all enquiries solved / tracked chats x 100.'],
      ['Escalation rate', 'Chats with accepted escalation / tracked chats x 100; independent of resolution.'],
      ['Categories', 'A chat may have multiple categories.'],
      ['Conversations sheet', 'Tracked chats only; the cohort used for outcome rates, categories and daily counts.'],
      ['Escalations sheet', 'All accepted events for the tracked cohort, including events after the period. Rates count each chat once.'],
      ['Usage scope', 'Calls within the selected period, independently of when the conversation started. Input tokens include cache tokens.'],
      ['Cache hit rate', 'Ratio 0–1: cache-read tokens / input tokens for calls with both measurements.'],
      ['Estimate notes', 'Public rates at each call; missing usage/rates excluded from subtotals. Excludes other charges, discounts and taxes.'],
      ['Missing data', 'Unavailable is not zero. No Guardrails calls means not applicable. No rows means no recorded activity.']
    ]
  end

  def usage_sheet(name, columns)
    rows = if @usage
             [['Total', *columns.map { |key| @usage.dig('total', key) }]] +
               @usage.fetch('days', []).map { |day| [day['group'], *columns.map { |key| day[key] }] }
           else
             [[MISSING, *columns.map { nil }]]
           end
    table(name, ['Date / total', *columns.map { |key| key.underscore.humanize }], rows)
  end

  def conversation_sheet
    rows = @rows.map do |row|
      [row.conversation.display_id, local_time(row.created_at), row.categories.join('; '), local_time(row.escalated_at),
       row.escalations.pluck('reason').uniq.join('; '), row.escalations.last&.fetch('destination', nil),
       local_time(row.closed_at), row.closed_at.present? && row.all_solved, row.enquiries.length]
    end
    table('Conversations', %w[Conversation First_handled_at Categories Escalated_at Reasons Destination Closed_at Solved_and_closed Enquiries], rows)
  end

  def escalation_sheet
    rows = @rows.flat_map do |row|
      row.escalations.map do |event|
        [row.conversation.display_id, local_time(event['at']), event['reason'], event['destination'], event['consentMessageId'],
         event['message_id'], row.categories.join('; '), row.closed_at.present? && row.all_solved]
      end
    end
    table('Escalations', %w[Conversation Accepted_at_ISO8601 Reason Destination Consent_message Reply_message Categories Solved_and_closed], rows)
  end

  def local_time(value)
    value&.in_time_zone(@timezone)&.iso8601
  end

  def cell_type(value)
    case value
    when Integer then :integer
    when Numeric then :float
    when TrueClass, FalseClass then :boolean
    else :string
    end
  end

  def add_rows(sheet, rows)
    rows.each do |row|
      cells = row.map { |value| value.nil? ? MISSING : value }
      # Source text must never become a spreadsheet formula.
      sheet.add_row(cells, types: cells.map { |value| cell_type(value) }, escape_formulas: true)
    end
  end

  def table(name, headers, rows, widths: nil)
    @book.add_worksheet(name: name) do |sheet|
      sheet.add_row(headers, style: @header)
      add_rows(sheet, rows)
      sheet.column_widths(*(widths || headers.map { |label| [label.length + 2, 26].max }))
      sheet.sheet_view.pane do |pane|
        pane.top_left_cell = 'A2'
        pane.y_split = 1
        pane.state = :frozen
        pane.active_pane = :bottom_left
      end
      sheet.auto_filter = "A1:#{Axlsx.col_ref(headers.length - 1)}#{rows.length + 1}"
    end
  end
end
