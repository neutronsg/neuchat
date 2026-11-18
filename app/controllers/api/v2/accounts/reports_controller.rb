class Api::V2::Accounts::ReportsController < Api::V1::Accounts::BaseController
  include Api::V2::Accounts::ReportsHelper
  include Api::V2::Accounts::HeatmapHelper

  before_action :check_authorization

  def index
    builder = V2::Reports::Conversations::ReportBuilder.new(Current.account, report_params)
    data = builder.timeseries
    render json: data
  end

  def summary
    render json: build_summary(:summary)
  end

  def bot_summary
    render json: build_summary(:bot_summary)
  end

  def agents
    @report_data = generate_agents_report
    generate_csv('agents_report', 'api/v2/accounts/reports/agents')
  end

  def inboxes
    @report_data = generate_inboxes_report
    generate_csv('inboxes_report', 'api/v2/accounts/reports/inboxes')
  end

  def labels
    @report_data = generate_labels_report
    generate_csv('labels_report', 'api/v2/accounts/reports/labels')
  end

  def teams
    @report_data = generate_teams_report
    generate_csv('teams_report', 'api/v2/accounts/reports/teams')
  end

  def conversation_traffic
    @report_data = generate_conversations_heatmap_report
    timezone_offset = (params[:timezone_offset] || 0).to_f
    @timezone = ActiveSupport::TimeZone[timezone_offset]

    generate_csv('conversation_traffic_reports', 'api/v2/accounts/reports/conversation_traffic')
  end

  def conversations
    return head :unprocessable_entity if params[:type].blank?

    render json: conversation_metrics
  end

  def bot_metrics
    BotUsageReportClient.period(from: params[:since], to: params[:until]) if oca_report?
    bot_metrics = V2::Reports::BotMetricsBuilder.new(Current.account, params).metrics
    render json: bot_metrics.merge(oca_reports_enabled: oca_report?)
  rescue ArgumentError, TypeError
    render json: { error: 'invalid_range' }, status: :unprocessable_entity
  end

  def bot_outcomes
    return head :not_found unless oca_report?

    render json: V2::Reports::BotOutcomesBuilder.new(Current.account, params).build
  rescue ArgumentError, TypeError
    render json: { error: 'invalid_range' }, status: :unprocessable_entity
  end

  def bot_outcomes_csv
    return head :not_found unless oca_report?

    send_data V2::Reports::BotOutcomesBuilder.new(Current.account, params).csv, filename: 'bot_conversations.csv', type: 'text/csv'
  rescue ArgumentError, TypeError
    render json: { error: 'invalid_range' }, status: :unprocessable_entity
  end

  def bot_usage
    return head :not_found unless oca_report?

    BotUsageReportClient.period(params)
    render json: BotUsageReportClient.fetch(Current.account.id, params)
  rescue ArgumentError, TypeError
    render json: { error: 'invalid_range' }, status: :unprocessable_entity
  rescue StandardError
    render json: { error: 'usage_unavailable' }, status: :service_unavailable
  end

  private

  def oca_report?
    ENV['OCA_BOT_REPORTS_ENABLED'] == 'true' && Current.account.id.to_s == ENV['OCA_BOT_ACCOUNT_ID']
  end

  def generate_csv(filename, template)
    response.headers['Content-Type'] = 'text/csv'
    response.headers['Content-Disposition'] = "attachment; filename=#{filename}.csv"
    render layout: false, template: template, formats: [:csv]
  end

  def check_authorization
    authorize :report, :view?
  end

  def common_params
    {
      type: params[:type].to_sym,
      id: params[:id],
      group_by: params[:group_by],
      business_hours: ActiveModel::Type::Boolean.new.cast(params[:business_hours])
    }
  end

  def current_summary_params
    common_params.merge({
                          since: range[:current][:since],
                          until: range[:current][:until],
                          timezone_offset: params[:timezone_offset]
                        })
  end

  def previous_summary_params
    common_params.merge({
                          since: range[:previous][:since],
                          until: range[:previous][:until],
                          timezone_offset: params[:timezone_offset]
                        })
  end

  def report_params
    common_params.merge({
                          metric: params[:metric],
                          since: params[:since],
                          until: params[:until],
                          timezone_offset: params[:timezone_offset]
                        })
  end

  def conversation_params
    {
      type: params[:type].to_sym,
      user_id: params[:user_id],
      page: params[:page].presence || 1
    }
  end

  def range
    {
      current: {
        since: params[:since],
        until: params[:until]
      },
      previous: {
        since: (params[:since].to_i - (params[:until].to_i - params[:since].to_i)).to_s,
        until: params[:since]
      }
    }
  end

  def build_summary(method)
    builder = V2::Reports::Conversations::MetricBuilder
    current_summary = builder.new(Current.account, current_summary_params).send(method)
    previous_summary = builder.new(Current.account, previous_summary_params).send(method)
    current_summary.merge(previous: previous_summary)
  end

  def conversation_metrics
    V2::ReportBuilder.new(Current.account, conversation_params).conversation_metrics
  end
end
