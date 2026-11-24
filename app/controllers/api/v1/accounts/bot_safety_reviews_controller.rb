class Api::V1::Accounts::BotSafetyReviewsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization?
  before_action :enabled!
  before_action :load_run, only: [:show, :resume, :export, :download, :annotate]

  def index
    render json: BotSafetyReviewRun.where(account: Current.account).order(id: :desc).limit(50).map { |run| summary(run) }
  end

  def profiles
    render json: BotSafetyReviews::Client.call(Current.account.id, '/internal/safety/review_profiles')
  rescue StandardError
    render json: { error: 'review_service_unavailable' }, status: :service_unavailable
  end

  def show
    items = @run.items.where('id > ?', params[:after].to_i).order(:id).limit(50)
    items = items.where("result #>> '{result,verdict}' IN (?)", %w[possible_false_positive possible_false_negative]) if params[:findings] == 'true'
    render json: summary(@run).merge(items: items.map { |item|
      item.as_json(only: [:id, :conversation_id, :message_id, :status, :result]).merge(
        notes: item.notes.order(:id).as_json(only: [:user_id, :verdict, :note, :created_at])
      )
    })
  end

  def create
    run = BotSafetyReviews::Create.call(Current.account, current_user,
                                        params.permit(:from_date, :to_date, :timezone, :profile, :scope, :max_requests, :max_calls,
                                                      :idempotency_key, :dry_run).to_h.symbolize_keys)
    render json: summary(run), status: :accepted
  rescue ArgumentError, KeyError, ActiveRecord::RecordInvalid
    render json: { error: 'invalid_review_settings' }, status: :unprocessable_entity
  rescue ActiveRecord::RecordNotUnique
    render json: { error: 'concurrent_request_retry' }, status: :conflict
  rescue IOError
    render json: { error: 'review_service_unavailable' }, status: :service_unavailable
  end

  def resume
    return head :conflict unless @run.resumable?

    BotSafetyReviews::RunJob.perform_later(@run.id)
    render json: summary(@run), status: :accepted
  end

  def export
    return head :conflict unless %w[completed incomplete failed].include?(@run.status)

    BotSafetyReviews::ExportJob.perform_later(@run.id)
    head :accepted
  end

  def download
    return head :not_found unless @run.export_file.attached?

    Rails.logger.info({ event: 'safety_review_download', account_id: Current.account.id, user_id: current_user.id, run_id: @run.id }.to_json)
    # Authenticated proxy; do not return a reusable public storage URL.
    send_data @run.export_file.download, filename: @run.export_file.filename.to_s, type: 'application/zip', disposition: 'attachment'
  end

  def annotate
    item = @run.items.find(params[:item_id])
    note = item.notes.create!(user: current_user, verdict: params.require(:verdict), note: params.require(:review_note))
    render json: note.as_json(only: [:id, :verdict, :note, :created_at]), status: :created
  rescue ActiveRecord::RecordInvalid
    render json: { error: 'invalid_review_note' }, status: :unprocessable_entity
  end

  private

  def load_run
    @run = BotSafetyReviewRun.where(account: Current.account).find(params[:id])
  end

  def enabled!
    head :not_found unless ENV['OCA_BOT_REPORTS_ENABLED'] == 'true' && BotSafetyClient.enabled?(Current.account.id)
  end

  def summary(run)
    run.as_json(only: [:id, :status, :settings, :summary, :calls_reserved, :export_status, :created_at, :updated_at]).merge(
      can_resume: run.resumable?, export_ready: run.export_file.attached?, counts: run.items.group(:status).count
    )
  end
end
