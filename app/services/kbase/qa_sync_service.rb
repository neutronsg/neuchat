class Kbase::QaSyncService
  QA_SEPARATOR = '------'.freeze
  QA_DOCUMENT_NAME = 'Q&A'.freeze
  QA_DOCUMENT_FILENAME = 'Q&A.docx'.freeze

  def initialize(knowledge_base)
    @kb = knowledge_base
    @client = Kbase::NeuaiClient.new
  end

  def sync!
    return if @kb.neuai_dataset_id.blank?
    return if @kb.qa_pairs.empty?

    qa_docx_file = build_qa_docx

    recreate_document(qa_docx_file)
  ensure
    qa_docx_file&.close!
  end

  def needs_sync?
    return false if @kb.qa_pairs.empty?

    last_qa_update = @kb.qa_pairs.maximum(:updated_at)
    return true if @kb.qa_document_id.blank?

    # If any Q&A was updated after the KB was last synced
    last_qa_update > @kb.updated_at
  end

  def processing?
    return false if @kb.qa_document_id.blank?

    response = @client.get_document(@kb.neuai_dataset_id, @kb.qa_document_id)
    indexing_status = response['indexing_status']
    processing_statuses = %w[waiting parsing cleaning splitting indexing]
    processing_statuses.include?(indexing_status)
  rescue Kbase::NeuaiClient::Error
    false
  end

  def document_status
    return nil if @kb.qa_document_id.blank?

    response = @client.get_document(@kb.neuai_dataset_id, @kb.qa_document_id)
    {
      indexing_status: response['indexing_status'],
      display_status: display_status(response['indexing_status']),
      enabled: response['enabled'],
      word_count: response['word_count']
    }
  rescue Kbase::NeuaiClient::Error
    nil
  end

  private

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

  def build_qa_docx
    qa_pairs = @kb.qa_pairs.ordered.map do |qa|
      { question: qa.question, answer: qa.answer }
    end

    Kbase::QaDocxBuilder.new(qa_pairs, separator: QA_SEPARATOR).build
  end

  def recreate_document(docx_file)
    delete_existing_document if @kb.qa_document_id.present?
    create_new_document(docx_file)
  end

  def delete_existing_document
    @client.delete_document(@kb.neuai_dataset_id, @kb.qa_document_id)
  rescue Kbase::NeuaiClient::ApiError => e
    raise unless e.status == 404
  end

  def create_new_document(docx_file)
    response = File.open(docx_file.path, 'rb') do |file|
      @client.create_document_by_file(
        @kb.neuai_dataset_id,
        file,
        name: QA_DOCUMENT_NAME,
        separator: QA_SEPARATOR,
        upload_filename: QA_DOCUMENT_FILENAME
      )
    end

    document_id = response.dig('document', 'id')
    @kb.update!(qa_document_id: document_id)
  end
end
