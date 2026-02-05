class Api::V1::Accounts::KnowledgeBases::QaPairsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization
  before_action :set_knowledge_base
  before_action :set_qa_pair, only: [:update, :destroy]

  def index
    @qa_pairs = @knowledge_base.qa_pairs.ordered
    render json: {
      qa_pairs: @qa_pairs.map { |qa| qa_pair_response(qa) },
      sync_required: sync_service.needs_sync?,
      qa_document_id: @knowledge_base.qa_document_id,
      qa_document_status: sync_service.document_status
    }
  end

  def create
    @qa_pair = @knowledge_base.qa_pairs.create!(
      qa_pair_params.merge(
        created_by_id: Current.user&.id,
        updated_by_id: Current.user&.id
      )
    )
    render json: qa_pair_response(@qa_pair), status: :created
  end

  def update
    @qa_pair.update!(
      qa_pair_params.merge(
        updated_by_id: Current.user&.id
      )
    )
    render json: qa_pair_response(@qa_pair)
  end

  def destroy
    @qa_pair.destroy
    head :no_content
  end

  def sync
    if sync_service.processing?
      render json: { error: 'Document is being processed, please try again later' }, status: :unprocessable_entity
      return
    end

    sync_service.sync!
    render json: {
      success: true,
      qa_document_id: @knowledge_base.reload.qa_document_id
    }
  rescue Kbase::NeuaiClient::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_knowledge_base
    @knowledge_base = Current.account.knowledge_bases.find(params[:knowledge_basis_id])
  end

  def set_qa_pair
    @qa_pair = @knowledge_base.qa_pairs.find(params[:id])
  end

  def check_admin_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end

  def qa_pair_params
    params.require(:qa_pair).permit(:question, :answer, :position)
  end

  def qa_pair_response(qa_pair)
    {
      id: qa_pair.id,
      question: qa_pair.question,
      answer: qa_pair.answer,
      position: qa_pair.position,
      created_at: qa_pair.created_at,
      updated_at: qa_pair.updated_at,
      updated_by: user_response(qa_pair.updated_by),
      created_by: user_response(qa_pair.created_by)
    }
  end

  def user_response(user)
    return nil unless user

    {
      id: user.id,
      name: user.name,
      email: user.email
    }
  end

  def sync_service
    @sync_service ||= Kbase::QaSyncService.new(@knowledge_base)
  end
end
