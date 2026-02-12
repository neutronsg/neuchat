require 'rails_helper'
require 'zip'

RSpec.describe Kbase::QaDocxImportService do
  describe '#parse!' do
    it 'parses qa pairs from docx generated with separator format' do
      source_pairs = [
        { question: 'How to reset password?', answer: 'Go to settings > security.' },
        {
          question: 'Do you support images?',
          answer: 'Yes, images are supported in Q&A content.'
        }
      ]

      docx_file = Kbase::QaDocxBuilder.new(source_pairs).build
      parsed_pairs = described_class.new(docx_file).parse!

      expect(parsed_pairs).to eq(source_pairs)
    ensure
      docx_file&.close!
    end

    it 'parses embedded images from docx and appends image url into answer' do
      docx_file = build_docx_with_embedded_image(
        Rails.root.join('spec/assets/avatar.png')
      )

      parsed_pairs = described_class.new(docx_file).parse!

      expect(parsed_pairs.length).to eq(1)
      expect(parsed_pairs.first[:question]).to eq('Can I upload docx with image?')
      expect(parsed_pairs.first[:answer]).to include('Yes, supported.')
      expect(parsed_pairs.first[:answer]).to match(%r{!\[image-1\]\(http://localhost:3000/rails/active_storage/})
    ensure
      docx_file&.close!
    end

    it 'raises when file is not a valid docx archive' do
      invalid_file = Tempfile.new(['invalid-qa', '.docx'])
      invalid_file.write('not a valid docx')
      invalid_file.rewind

      expect do
        described_class.new(invalid_file).parse!
      end.to raise_error(Kbase::QaDocxImportService::Error)
    ensure
      invalid_file&.close!
    end
  end

  def build_docx_with_embedded_image(image_path)
    docx_file = Tempfile.new(['qa-inline-image', '.docx'])
    docx_file.binmode
    docx_file.close

    Zip::File.open(docx_file.path, create: true) do |zip|
      zip.get_output_stream('[Content_Types].xml') { |s| s.write(content_types_xml) }
      zip.get_output_stream('_rels/.rels') { |s| s.write(root_relationships_xml) }
      zip.get_output_stream('word/document.xml') { |s| s.write(document_with_image_xml) }
      zip.get_output_stream('word/_rels/document.xml.rels') { |s| s.write(document_relationships_xml) }
      zip.get_output_stream('word/media/image1.png') { |s| s.write(File.binread(image_path)) }
    end

    docx_file
  end

  def content_types_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Default Extension="png" ContentType="image/png"/>
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      </Types>
    XML
  end

  def root_relationships_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
      </Relationships>
    XML
  end

  def document_relationships_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rIdImage1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/>
      </Relationships>
    XML
  end

  def document_with_image_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <w:document
        xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
        xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">
        <w:body>
          <w:p><w:r><w:t>Question: Can I upload docx with image?</w:t></w:r></w:p>
          <w:p><w:r><w:t>Answer: Yes, supported.</w:t></w:r></w:p>
          <w:p>
            <w:r>
              <w:drawing>
                <a:blip r:embed="rIdImage1"/>
              </w:drawing>
            </w:r>
          </w:p>
        </w:body>
      </w:document>
    XML
  end
end
