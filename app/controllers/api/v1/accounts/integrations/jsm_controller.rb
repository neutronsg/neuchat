class Api::V1::Accounts::Integrations::JsmController < Api::V1::Accounts::BaseController
  before_action :ensure_api_access_token!
  before_action :check_admin_authorization?
  before_action :fetch_conversation
  before_action :fetch_hook

  def link_ticket
    if permitted_params[:ticket_id].blank? && permitted_params[:ticket_key].blank?
      return render json: { error: 'ticket_id or ticket_key is required' }, status: :unprocessable_entity
    end

    jsm_attributes = {
      'ticket_id' => permitted_params[:ticket_id],
      'ticket_key' => permitted_params[:ticket_key],
      'ticket_url' => permitted_params[:ticket_url]
    }.compact

    @conversation.additional_attributes = @conversation.additional_attributes.to_h
    @conversation.additional_attributes['jsm'] = jsm_attributes
    @conversation.save!

    render json: {
      conversation_id: @conversation.id,
      jsm: @conversation.additional_attributes['jsm']
    }, status: :ok
  end

  private

  def ensure_api_access_token!
    return if request.headers[:api_access_token].present? || request.headers[:HTTP_API_ACCESS_TOKEN].present?

    render_unauthorized('api_access_token is required')
  end

  def fetch_conversation
    conversation_id = permitted_params[:conversation_id]
    @conversation = Current.account.conversations.find_by(id: conversation_id) ||
                    Current.account.conversations.find_by!(display_id: conversation_id)
  end

  def fetch_hook
    @hook = Current.account.hooks.enabled.find_by!(app_id: 'jsm')
  end

  def permitted_params
    params.permit(:conversation_id, :ticket_id, :ticket_key, :ticket_url)
  end
end
