class Api::V1::Accounts::LabelsController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action :fetch_label, except: [:index, :create]
  before_action :check_authorization

  def index
    @labels = policy_scope(Current.account.labels)
  end

  def show; end

  def create
    Current.account.with_lock { @label = Current.account.labels.create!(permitted_params) }
  end

  def update
    Current.account.with_lock { @label.reload.update!(permitted_params) }
  end

  def destroy
    Current.account.with_lock { @label.reload.destroy! }
    head :ok
  rescue ActiveRecord::RecordNotDestroyed => e
    render json: { error: e.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end

  private

  def fetch_label
    @label = Current.account.labels.find(params[:id])
  end

  def permitted_params
    params.require(:label).permit(:title, :description, :color, :show_on_sidebar, :ai_category, :ai_category_name)
  end
end
