require 'rails_helper'
require 'zip'

RSpec.describe Kbase::QaDocxBuilder do
  describe '#build' do
    it 'builds a docx with question/answer markers and separator' do
      qa_pairs = [
        { question: 'What is NeuChat?', answer: 'A support assistant.' },
        {
          question: 'Can I embed image?',
          answer: 'Yes, screenshots are supported.'
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

    it 'embeds markdown image urls into docx media for dify ingestion' do
      qa_pairs = [{
        question: 'Can I include screenshots?',
        answer: 'Yes, see this ![image](https://example.com/image.png)'
      }]
      downloaded_image = build_png_tempfile

      allow(Down).to receive(:download).with('https://example.com/image.png').and_return(downloaded_image)

      docx_file = described_class.new(qa_pairs).build
      docx_entries = read_docx_entries(
        docx_file,
        'word/_rels/document.xml.rels',
        'word/document.xml',
        '[Content_Types].xml',
        'word/media/image1.png'
      )

      expect(docx_entries['word/media/image1.png']).to eq('fake-png-binary')
      expect(docx_entries['word/document.xml']).to include('r:embed="rIdImage1"')
      expect(docx_entries['word/_rels/document.xml.rels']).to include('Id="rIdImage1"')
      expect(docx_entries['word/_rels/document.xml.rels']).to include('Target="media/image1.png"')
      expect(docx_entries['[Content_Types].xml']).to include('Extension="png"')
    ensure
      downloaded_image&.close!
      docx_file&.close!
    end
  end

  def build_png_tempfile(content = 'fake-png-binary')
    tempfile = Tempfile.new(['qa-docx-image', '.png'])
    tempfile.binmode
    tempfile.write(content)
    tempfile.rewind
    tempfile
  end

  def read_docx_entries(docx_file, *entry_paths)
    Zip::File.open(docx_file.path) do |zip|
      entry_paths.index_with { |path| zip.read(path) }
    end
  end
end
