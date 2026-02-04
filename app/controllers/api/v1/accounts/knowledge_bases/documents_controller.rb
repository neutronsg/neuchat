class Api::V1::Accounts::KnowledgeBases::DocumentsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization
  before_action :set_knowledge_base
  before_action :set_document, only: [:update, :destroy]

  def index
    sync_documents_from_neuai
    @documents = @knowledge_base.documents.ordered
    render json: { documents: documents_response }
  end

  def create
    return render_error('No file uploaded', :bad_request) if params[:file].blank?

    client = Kbase::NeuaiClient.new
    response = client.create_document_by_file(
      @knowledge_base.neuai_dataset_id,
      params[:file],
      name: params[:name] || params[:file].original_filename
    )

    document = @knowledge_base.documents.create!(
      neuai_document_id: response.dig('document', 'id'),
      name: params[:name] || params[:file].original_filename,
      created_by_id: Current.user&.id,
      updated_by_id: Current.user&.id
    )

    render json: document_response(document, response['document']), status: :created
  rescue Kbase::NeuaiClient::Error => e
    render_error(e.message, :unprocessable_entity)
  end

  def update
    action = params[:enabled] ? 'enable' : 'disable'
    client = Kbase::NeuaiClient.new
    client.update_document_status(
      @knowledge_base.neuai_dataset_id,
      @document.neuai_document_id,
      action: action
    )

    @document.update!(updated_by_id: Current.user&.id)

    render json: { success: true }
  rescue Kbase::NeuaiClient::Error => e
    render_error(e.message, :unprocessable_entity)
  end

  def destroy
    client = Kbase::NeuaiClient.new
    client.delete_document(@knowledge_base.neuai_dataset_id, @document.neuai_document_id)
    @document.destroy

    head :no_content
  rescue Kbase::NeuaiClient::Error => e
    render_error(e.message, :unprocessable_entity)
  end

  private

  def set_knowledge_base
    @knowledge_base = Current.account.knowledge_bases.find(params[:knowledge_basis_id])
  end

  def set_document
    @document = @knowledge_base.documents.find(params[:id])
  end

  def check_admin_authorization
    raise Pundit::NotAuthorizedError unless Current.account_user&.administrator?
  end

  def sync_documents_from_neuai
    return if @knowledge_base.neuai_dataset_id.blank?

    client = Kbase::NeuaiClient.new
    response = client.list_documents(@knowledge_base.neuai_dataset_id)
    @neuai_documents = response['data'] || []
  rescue Kbase::NeuaiClient::Error
    @neuai_documents = []
  end

  def documents_response
    @knowledge_base.documents.ordered.map do |doc|
      neuai_doc = @neuai_documents&.find { |d| d['id'] == doc.neuai_document_id }
      document_response(doc, neuai_doc)
    end
  end

  def document_response(doc, neuai_doc = nil)
    {
      id: doc.id,
      name: doc.name,
      neuai_document_id: doc.neuai_document_id,
      indexing_status: neuai_doc&.dig('indexing_status') || 'unknown',
      enabled: neuai_doc&.dig('enabled') || true,
      word_count: neuai_doc&.dig('word_count') || 0,
      created_at: doc.created_at,
      updated_at: doc.updated_at,
      updated_by: user_response(doc.updated_by),
      created_by: user_response(doc.created_by)
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

  def render_error(message, status)
    render json: { error: message }, status: status
  end
end
