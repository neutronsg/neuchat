class Api::V1::Accounts::AgentBotsController < Api::V1::Accounts::BaseController
  class SafetyConflict < StandardError; end
  class SafetyUnavailable < StandardError; end
  before_action :current_account
  before_action :check_authorization
  before_action :agent_bot, except: [:index, :create, :safety_options]

  def index
    @agent_bots = AgentBot.where(account_id: [nil, Current.account.id])
  end

  def show; end

  def safety_options
    render json: BotSafetyClient.fetch(Current.account.id, '/internal/safety/capabilities')
  rescue StandardError
    render json: { error: 'safety_service_unavailable' }, status: :service_unavailable
  end

  def create
    @agent_bot = Current.account.agent_bots.create!(permitted_params.except(:avatar_url))
    process_avatar_from_url
  end

  def update
    attributes = permitted_params.except(:avatar_url)
    capabilities = BotSafetyClient.fetch(Current.account.id, '/internal/safety/capabilities') if attributes.key?(:safety_mode)
    @agent_bot.with_lock do
      validate_safety_change!(attributes, capabilities)
      @agent_bot.update!(attributes)
    end
    process_avatar_from_url
  rescue SafetyConflict
    render json: { error: 'safety_configuration_changed' }, status: :conflict
  rescue SafetyUnavailable
    render json: { error: 'safety_mode_unavailable' }, status: :unprocessable_entity
  rescue IOError, KeyError, ArgumentError, SocketError, Timeout::Error
    render json: { error: 'safety_service_unavailable' }, status: :service_unavailable
  end

  def avatar
    @agent_bot.avatar.purge if @agent_bot.avatar.attached?
    @agent_bot
  end

  def destroy
    @agent_bot.destroy!
    head :ok
  end

  def reset_access_token
    @agent_bot.access_token.regenerate_token
    @agent_bot.reload
  end

  private

  def validate_safety_change!(attributes, capabilities)
    return unless attributes.key?(:safety_mode) && attributes[:safety_mode] != @agent_bot.safety_mode

    raise SafetyConflict unless params[:safety_version].to_s == @agent_bot.safety_version.to_s
    raise SafetyUnavailable unless capabilities.fetch('modes').include?(attributes[:safety_mode])
  end

  def agent_bot
    @agent_bot = AgentBot.where(account_id: [nil, Current.account.id]).find(params[:id]) if params[:action] == 'show'
    @agent_bot ||= Current.account.agent_bots.find(params[:id])
  end

  def permitted_params
    permitted = params.permit(:name, :description, :outgoing_url, :avatar, :avatar_url, :bot_type,
                              :idle_auto_resolve_enabled, :idle_auto_resolve_after, :safety_mode, bot_config: {})
    permitted.delete(:safety_mode) if action_name == 'create'
    if %w[true false].include?(permitted[:idle_auto_resolve_enabled])
      permitted[:idle_auto_resolve_enabled] = permitted[:idle_auto_resolve_enabled] == 'true'
    end
    permitted
  end

  def process_avatar_from_url
    ::Avatar::AvatarFromUrlJob.perform_later(@agent_bot, params[:avatar_url]) if params[:avatar_url].present?
  end
end
