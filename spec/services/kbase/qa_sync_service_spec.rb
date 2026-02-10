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
    it 'creates QA document with fixed Q&A name' do
      Kbase::QaPair.create!(
        knowledge_base: knowledge_base,
        question: 'What is this?',
        answer: 'A support article.'
      )

      expect(neuai_client).to receive(:create_document_by_file).with(
        'dataset_123',
        satisfy { |file| file.respond_to?(:path) && File.extname(file.path) == '.docx' },
        name: 'Q&A',
        separator: '------',
        upload_filename: 'Q&A.docx'
      ).and_return({ 'document' => { 'id' => 'qa_doc_1' } })

      described_class.new(knowledge_base).sync!

      expect(knowledge_base.reload.qa_document_id).to eq('qa_doc_1')
    end

    it 'deletes old QA document then creates a new one on update' do
      knowledge_base.update!(qa_document_id: 'qa_doc_existing')
      Kbase::QaPair.create!(
        knowledge_base: knowledge_base,
        question: 'How to reset password?',
        answer: 'Go to settings.'
      )

      expect(neuai_client).to receive(:delete_document).with(
        'dataset_123',
        'qa_doc_existing'
      )
      expect(neuai_client).to receive(:create_document_by_file).with(
        'dataset_123',
        satisfy { |file| file.respond_to?(:path) && File.extname(file.path) == '.docx' },
        name: 'Q&A',
        separator: '------',
        upload_filename: 'Q&A.docx'
      ).and_return({ 'document' => { 'id' => 'qa_doc_new' } })

      described_class.new(knowledge_base).sync!

      expect(knowledge_base.reload.qa_document_id).to eq('qa_doc_new')
    end

    it 'continues create flow when old QA document is already missing' do
      knowledge_base.update!(qa_document_id: 'qa_doc_missing')
      Kbase::QaPair.create!(
        knowledge_base: knowledge_base,
        question: 'How to reset password?',
        answer: 'Go to settings.'
      )

      expect(neuai_client).to receive(:delete_document).with(
        'dataset_123',
        'qa_doc_missing'
      ).and_raise(Kbase::NeuaiClient::ApiError.new('not found', status: 404))
      expect(neuai_client).to receive(:create_document_by_file).with(
        'dataset_123',
        satisfy { |file| file.respond_to?(:path) && File.extname(file.path) == '.docx' },
        name: 'Q&A',
        separator: '------',
        upload_filename: 'Q&A.docx'
      ).and_return({ 'document' => { 'id' => 'qa_doc_new' } })

      described_class.new(knowledge_base).sync!

      expect(knowledge_base.reload.qa_document_id).to eq('qa_doc_new')
    end
  end
end
