require 'nokogiri'
require 'tempfile'
require 'zip'

class Kbase::QaDocxBuilder
  WORD_NAMESPACE = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'.freeze

  def initialize(qa_pairs, separator: '------')
    @qa_pairs = qa_pairs
    @separator = separator
  end

  def build
    docx_file = Tempfile.new(['qa-sync', '.docx'])
    docx_file.binmode
    docx_file.close

    Zip::File.open(docx_file.path, create: true) do |zip|
      write_entry(zip, '[Content_Types].xml', content_types_xml)
      write_entry(zip, '_rels/.rels', root_relationships_xml)
      write_entry(zip, 'word/document.xml', document_xml)
      write_entry(zip, 'word/_rels/document.xml.rels', empty_relationships_xml)
    end

    docx_file
  rescue StandardError
    docx_file&.close!
    raise
  end

  private

  def write_entry(zip, path, content)
    zip.get_output_stream(path) { |stream| stream.write(content) }
  end

  def qa_lines
    lines = []
    @qa_pairs.each_with_index do |qa, index|
      lines << 'Question:'
      lines.concat(multiline(qa[:question]))
      lines << 'Answer:'
      lines.concat(multiline(qa[:answer]))
      lines << @separator if index < @qa_pairs.length - 1
    end
    lines
  end

  def multiline(value)
    value.to_s.split(/\r?\n/, -1).presence || ['']
  end

  def document_xml
    Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
      xml['w'].document('xmlns:w' => WORD_NAMESPACE) do
        xml['w'].body do
          append_paragraphs(xml)
          append_section_properties(xml)
        end
      end
    end.to_xml
  end

  def append_paragraphs(xml)
    qa_lines.each do |line|
      xml['w'].p do
        xml['w'].r do
          xml['w'].t(line, 'xml:space' => 'preserve')
        end
      end
    end
  end

  def append_section_properties(xml)
    xml['w'].sectPr do
      xml['w'].pgSz('w:w' => '12240', 'w:h' => '15840')
      xml['w'].pgMar(
        'w:top' => '1440',
        'w:right' => '1440',
        'w:bottom' => '1440',
        'w:left' => '1440',
        'w:header' => '720',
        'w:footer' => '720',
        'w:gutter' => '0'
      )
    end
  end

  def content_types_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
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

  def empty_relationships_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>
    XML
  end
end
