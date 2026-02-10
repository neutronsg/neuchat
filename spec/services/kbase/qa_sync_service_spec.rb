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
    it 'uses docx file upload with ------ separator when creating QA document' do
      Kbase::QaPair.create!(
        knowledge_base: knowledge_base,
        question: 'What is this?',
        answer: 'A support article.'
      )

      expect(neuai_client).to receive(:create_document_by_file).with(
        'dataset_123',
        satisfy { |file| file.respond_to?(:path) && File.extname(file.path) == '.docx' },
        name: 'Support KB - Q&A',
        separator: '------'
      ).and_return({ 'document' => { 'id' => 'qa_doc_1' } })

      described_class.new(knowledge_base).sync!

      expect(knowledge_base.reload.qa_document_id).to eq('qa_doc_1')
    end

    it 'uses docx file upload with ------ separator when updating QA document' do
      knowledge_base.update!(qa_document_id: 'qa_doc_existing')
      Kbase::QaPair.create!(
        knowledge_base: knowledge_base,
        question: 'How to reset password?',
        answer: 'Go to settings.'
      )

      expect(neuai_client).to receive(:update_document_by_file).with(
        'dataset_123',
        'qa_doc_existing',
        satisfy { |file| file.respond_to?(:path) && File.extname(file.path) == '.docx' },
        name: 'Support KB - Q&A',
        separator: '------'
      )

      described_class.new(knowledge_base).sync!
    end
  end
end
