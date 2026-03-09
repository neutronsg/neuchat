class Api::V1::Accounts::KnowledgeBases::DocumentsController < Api::V1::Accounts::BaseController
  before_action :check_admin_authorization
  before_action :set_knowledge_base
  before_action :set_document, only: [:update, :destroy, :show_chunk_settings, :update_chunk_settings]

  PROCESSING_STATUSES = %w[waiting parsing cleaning splitting indexing].freeze

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
      name: params[:name] || params[:file].original_filename,
      process_rule: build_chunk_settings&.to_process_rule
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
  rescue Kbase::DocumentChunkSettings::Error => e
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

  def show_chunk_settings
    client = Kbase::NeuaiClient.new
    response = client.get_document(@knowledge_base.neuai_dataset_id, @document.neuai_document_id)

    render json: {
      chunk_settings: Kbase::DocumentChunkSettings.from_dify(
        document_process_rule: response['document_process_rule'],
        dataset_process_rule: response['dataset_process_rule']
      )
    }
  rescue Kbase::NeuaiClient::Error => e
    render_error(e.message, :unprocessable_entity)
  end

  def update_chunk_settings
    client = Kbase::NeuaiClient.new
    current_document = client.get_document(@knowledge_base.neuai_dataset_id, @document.neuai_document_id)
    return render_error('Document is being processed, please try again later', :unprocessable_entity) if processing?(current_document)

    chunk_settings = build_chunk_settings(required: true)
    response = client.update_document_by_file(
      @knowledge_base.neuai_dataset_id,
      @document.neuai_document_id,
      nil,
      name: @document.name || current_document['name'],
      process_rule: chunk_settings.to_process_rule
    )

    @document.update!(updated_by_id: Current.user&.id)

    render json: {
      success: true,
      indexing_status: response.dig('document', 'indexing_status') || 'waiting'
    }
  rescue Kbase::NeuaiClient::Error => e
    render_error(e.message, :unprocessable_entity)
  rescue Kbase::DocumentChunkSettings::Error => e
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
    indexing_status = neuai_doc&.dig('indexing_status') || 'unknown'
    {
      id: doc.id,
      name: doc.name,
      neuai_document_id: doc.neuai_document_id,
      indexing_status: indexing_status,
      display_status: display_status(indexing_status),
      enabled: neuai_doc&.dig('enabled').nil? || neuai_doc['enabled'],
      word_count: neuai_doc&.dig('word_count') || 0,
      created_at: doc.created_at,
      updated_at: doc.updated_at,
      updated_by: user_response(doc.updated_by),
      created_by: user_response(doc.created_by)
    }
  end

  def display_status(indexing_status)
    return 'unknown' if indexing_status.blank?

    case indexing_status
    when 'waiting', 'parsing', 'cleaning', 'splitting', 'indexing'
      'processing'
    when 'error'
      'error'
    when 'completed'
      'available'
    else
      'unknown'
    end
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

  def build_chunk_settings(required: false)
    return nil if !required && parsed_chunk_settings.blank?

    Kbase::DocumentChunkSettings.from_payload(parsed_chunk_settings)
  end

  def parsed_chunk_settings
    value = params[:chunk_settings]
    return {} if value.blank?
    return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)
    return value if value.is_a?(Hash)

    JSON.parse(value)
  rescue JSON::ParserError
    raise Kbase::DocumentChunkSettings::Error, 'Invalid chunk settings payload'
  end

  def processing?(document_response)
    PROCESSING_STATUSES.include?(document_response['indexing_status'])
  end
end
