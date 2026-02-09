class Kbase::QaSyncService
  QA_SEPARATOR = '------'.freeze

  def initialize(knowledge_base)
    @kb = knowledge_base
    @client = Kbase::NeuaiClient.new
  end

  def sync!
    return if @kb.neuai_dataset_id.blank?
    return if @kb.qa_pairs.empty?

    text = build_qa_text

    if @kb.qa_document_id.present?
      update_existing_document(text)
    else
      create_new_document(text)
    end
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

  def build_qa_text
    @kb.qa_pairs.ordered.map do |qa|
      "Question: #{qa.question}\nAnswer: #{qa.answer}"
    end.join("\n#{QA_SEPARATOR}\n")
  end

  def create_new_document(text)
    response = @client.create_document_by_text(
      @kb.neuai_dataset_id,
      name: "#{@kb.name} - Q&A",
      text: text,
      separator: QA_SEPARATOR
    )

    document_id = response.dig('document', 'id')
    @kb.update!(qa_document_id: document_id)
  end

  def update_existing_document(text)
    @client.update_document_by_text(
      @kb.neuai_dataset_id,
      @kb.qa_document_id,
      name: "#{@kb.name} - Q&A",
      text: text,
      separator: QA_SEPARATOR
    )
    @kb.touch # rubocop:disable Rails/SkipsModelValidations
  end
end
