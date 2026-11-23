require 'csv'
class V2::Reports::BotOutcomesBuilder
  def initialize(account, params)
    @account = account
    @timezone = BotUsageReportClient.timezone(params)
    @from = Time.at(Integer(params[:from])).utc
    @to = Time.at(Integer(params[:to])).utc
    raise ArgumentError, 'Invalid reporting period' unless @to > @from

    @params = params
  end

  def build
    rows = export_rows
    summary(rows).merge(days: days(rows), categories: rows.flat_map(&:categories).tally,
                        tracking_started_at: @account.bot_conversation_outcomes.minimum(:created_at), timezone: @timezone).merge(details(rows))
  end

  # One bounded, account-scoped snapshot shared by all workbook sheets.
  def export_rows
    return @export_rows if @export_rows

    rows = scope.includes(:conversation).order(:created_at, :id).limit(50_001).to_a
    raise BotReportLimitError, 'Reporting period too large' if rows.size > 50_000

    @export_rows = rows
  end

  def csv
    raise BotReportLimitError, 'Reporting period too large' if scope.count > 50_000

    CSV.generate do |csv|
      csv << %w[conversation_id handled_at categories escalated_at reasons destination closed_at all_solved]
      scope.includes(:conversation).find_each { |r| csv << csv_row(r).map { |v| csv_cell(v) } }
    end
  end

  private

  def summary(rows)
    { conversation_count: rows.size, resolution_rate: percentage(rows.count { |r| solved?(r) }, rows.size),
      escalation_rate: percentage(rows.count(&:escalated_at), rows.size) }
  end

  def days(rows)
    groups = rows.group_by { |r| r.created_at.in_time_zone(@timezone).to_date }
    range = @from.in_time_zone(@timezone).to_date..(@to - 1.second).in_time_zone(@timezone).to_date
    raise BotReportLimitError, 'Reporting period too large' if (range.end - range.begin).to_i >= 50_000

    range.map do |day|
      cohort = groups.fetch(day, [])
      { day: day.iso8601, conversations: cohort.size, resolutions: cohort.count { |r| solved?(r) }, escalations: cohort.count(&:escalated_at) }
    end
  end

  def details(rows)
    selected = rows.select(&:escalated_at).sort_by(&:escalated_at).reverse
    selected.select! { |r| r.escalations.any? { |e| e['reason'] == @params[:reason] } } if @params[:reason].present?
    page = [@params[:page].to_i, 1].max
    { detail_total: selected.size, page: page, details: selected.slice((page - 1) * 25, 25).to_a.map { |r| detail(r) } }
  end

  def scope
    @account.bot_conversation_outcomes.where(created_at: @from...@to)
  end

  def solved?(row)
    row.closed_at.present? && row.all_solved
  end

  def percentage(count, total)
    total.zero? ? 0 : (count.to_f / total * 100).round(1)
  end

  def detail(row)
    { conversation_id: row.conversation.display_id, escalated_at: row.escalated_at, categories: row.categories,
      reasons: row.escalations.pluck('reason').uniq, destination: row.escalations.last&.fetch('destination'), all_solved: solved?(row) }
  end

  def csv_row(row)
    data = detail(row)
    [data[:conversation_id], row.created_at.in_time_zone(@timezone).iso8601, data[:categories].join('; '),
     row.escalated_at&.in_time_zone(@timezone)&.iso8601,
     data[:reasons].join('; '), data[:destination], row.closed_at&.in_time_zone(@timezone)&.iso8601, data[:all_solved]]
  end

  def csv_cell(value)
    value.is_a?(String) && value.match?(/\A[\s]*[=+@-]/) ? "'#{value}" : value
  end
end
