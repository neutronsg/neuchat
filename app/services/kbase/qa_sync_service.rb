class Kbase::QaSyncService
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

  private

  def build_qa_text
    @kb.qa_pairs.ordered.map do |qa|
      "Question: #{qa.question}\nAnswer: #{qa.answer}"
    end.join("\n------\n")
  end

  def create_new_document(text)
    response = @client.create_document_by_text(
      @kb.neuai_dataset_id,
      name: "#{@kb.name} - Q&A",
      text: text
    )

    document_id = response.dig('document', 'id')
    @kb.update!(qa_document_id: document_id)
  end

  def update_existing_document(text)
    @client.update_document_by_text(
      @kb.neuai_dataset_id,
      @kb.qa_document_id,
      name: "#{@kb.name} - Q&A",
      text: text
    )
    @kb.touch # rubocop:disable Rails/SkipsModelValidations
  end
end
