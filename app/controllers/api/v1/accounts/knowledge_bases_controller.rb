class Api::V1::Accounts::KnowledgeBasesController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization
  before_action :set_knowledge_base, only: [:show]

  def index
    @knowledge_bases = Current.account.knowledge_bases.ordered
    render json: @knowledge_bases.map { |kb| knowledge_base_response(kb) }
  end

  def show
    render json: knowledge_base_response(@knowledge_base)
  end

  private

  def set_knowledge_base
    @knowledge_base = Current.account.knowledge_bases.find(params[:id])
  end

  def check_admin_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end

  def knowledge_base_response(knowledge_base)
    {
      id: knowledge_base.id,
      name: knowledge_base.name,
      description: knowledge_base.description,
      neuai_dataset_id: knowledge_base.neuai_dataset_id,
      documents_count: knowledge_base.documents.count,
      qa_pairs_count: knowledge_base.qa_pairs.count,
      created_at: knowledge_base.created_at,
      updated_at: knowledge_base.updated_at
    }
  end
end
