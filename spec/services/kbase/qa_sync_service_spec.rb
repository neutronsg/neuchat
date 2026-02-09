require 'rails_helper'

RSpec.describe Kbase::QaSyncService do
  let(:account) { create(:account) }
  let(:knowledge_base) do
    Kbase::KnowledgeBase.create!(
      account: account,
      name: 'Support KB',
      neuai_dataset_id: 'dataset_123'
    )
  end
  let(:neuai_client) { instance_double(Kbase::NeuaiClient) }

  before do
    allow(Kbase::NeuaiClient).to receive(:new).and_return(neuai_client)
  end

  describe '#sync!' do
    it 'uses ------ as separator when creating QA document' do
      Kbase::QaPair.create!(
        knowledge_base: knowledge_base,
        question: 'What is this?',
        answer: 'A support article.'
      )

      expect(neuai_client).to receive(:create_document_by_text).with(
        'dataset_123',
        name: 'Support KB - Q&A',
        text: "Question: What is this?\nAnswer: A support article.",
        separator: '------'
      ).and_return({ 'document' => { 'id' => 'qa_doc_1' } })

      described_class.new(knowledge_base).sync!

      expect(knowledge_base.reload.qa_document_id).to eq('qa_doc_1')
    end

    it 'uses ------ as separator when updating QA document' do
      knowledge_base.update!(qa_document_id: 'qa_doc_existing')
      Kbase::QaPair.create!(
        knowledge_base: knowledge_base,
        question: 'How to reset password?',
        answer: 'Go to settings.'
      )

      expect(neuai_client).to receive(:update_document_by_text).with(
        'dataset_123',
        'qa_doc_existing',
        name: 'Support KB - Q&A',
        text: "Question: How to reset password?\nAnswer: Go to settings.",
        separator: '------'
      )

      described_class.new(knowledge_base).sync!
    end
  end
end
