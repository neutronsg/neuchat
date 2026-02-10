class Kbase::QaSyncService
  QA_SEPARATOR = '------'.freeze

  def initialize(knowledge_base)
    @kb = knowledge_base
    @client = Kbase::NeuaiClient.new
  end

  def sync!
    return if @kb.neuai_dataset_id.blank?
    return if @kb.qa_pairs.empty?

    qa_docx_file = build_qa_docx

    if @kb.qa_document_id.present?
      update_existing_document(qa_docx_file)
    else
      create_new_document(qa_docx_file)
    end
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

  def create_new_document(docx_file)
    response = File.open(docx_file.path, 'rb') do |file|
      @client.create_document_by_file(
        @kb.neuai_dataset_id,
        file,
        name: "#{@kb.name} - Q&A",
        separator: QA_SEPARATOR
      )
    end

    document_id = response.dig('document', 'id')
    @kb.update!(qa_document_id: document_id)
  end

  def update_existing_document(docx_file)
    File.open(docx_file.path, 'rb') do |file|
      @client.update_document_by_file(
        @kb.neuai_dataset_id,
        @kb.qa_document_id,
        file,
        name: "#{@kb.name} - Q&A",
        separator: QA_SEPARATOR
      )
    end

    @kb.touch # rubocop:disable Rails/SkipsModelValidations
  end
end
