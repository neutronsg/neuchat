require 'rails_helper'
require 'zip'

RSpec.describe Kbase::QaDocxBuilder do
  describe '#build' do
    it 'builds a docx with question/answer markers and separator' do
      qa_pairs = [
        { question: 'What is NeuChat?', answer: 'A support assistant.' },
        {
          question: 'Can I embed image?',
          answer: 'Yes, use ![product](https://example.com/product.png)'
        }
      ]

      docx_file = described_class.new(qa_pairs).build

      expect(File.extname(docx_file.path)).to eq('.docx')

      document_xml = nil
      Zip::File.open(docx_file.path) do |zip|
        document_xml = zip.read('word/document.xml')
      end

      expect(document_xml).to include('Question:')
      expect(document_xml).to include('Answer:')
      expect(document_xml).to include('------')
    ensure
      docx_file&.close!
    end
  end
end
