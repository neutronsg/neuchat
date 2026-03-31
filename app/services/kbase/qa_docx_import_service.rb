require 'nokogiri'
require 'stringio'
require 'zip'

class Kbase::QaDocxImportService
  class Error < StandardError; end

  NAMESPACE = {
    'w' => 'http://schemas.openxmlformats.org/wordprocessingml/2006/main',
    'a' => 'http://schemas.openxmlformats.org/drawingml/2006/main',
    'r' => 'http://schemas.openxmlformats.org/officeDocument/2006/relationships',
    'rels' => 'http://schemas.openxmlformats.org/package/2006/relationships'
  }.freeze

  def initialize(file, separator: '------')
    @file = file
    @separator = separator
    @image_sequence = 0
  end

  def parse!
    text = with_docx_archive { extract_document_text }
    qa_pairs = parse_qa_pairs(text)

    raise Error, 'No valid Q&A pairs found in DOCX' if qa_pairs.empty?

    qa_pairs
  rescue Zip::Error, Nokogiri::XML::SyntaxError => e
    raise Error, "Invalid DOCX file: #{e.message}"
  end

  private

  def file_path
    @file.respond_to?(:path) ? @file.path : @file.tempfile.path
  end

  def with_docx_archive
    Zip::File.open(file_path) do |zip|
      @zip = zip
      @document_relationships = load_document_relationships
      yield
    end
  ensure
    @zip = nil
    @document_relationships = {}
  end

  def extract_document_text
    document_xml = read_docx_entry('word/document.xml')
    doc = Nokogiri::XML(document_xml)
    paragraphs = doc.xpath('//w:body/w:p', NAMESPACE).map do |paragraph|
      paragraph_content(paragraph)
    end
    paragraphs.join("\n")
  end

  def paragraph_content(paragraph)
    fragments = []

    paragraph.xpath('.//w:r', NAMESPACE).each do |run|
      run_text = run.xpath('.//w:t', NAMESPACE).map(&:text).join
      fragments << run_text if run_text.present?

      run.xpath('.//a:blip', NAMESPACE).each do |blip|
        image_markdown = markdown_image_for_blip(blip)
        fragments << image_markdown if image_markdown.present?
      end
    end

    fragments.join
  end

  def markdown_image_for_blip(blip)
    relationship_id = relationship_id_for_blip(blip)
    return nil if relationship_id.blank?

    image_url = upload_image_url(relationship_id)
    return nil if image_url.blank?

    @image_sequence += 1
    "![image-#{@image_sequence}](#{image_url})"
  end

  def relationship_id_for_blip(blip)
    blip.attribute_with_ns('embed', NAMESPACE['r'])&.value ||
      blip['r:embed'] ||
      blip['embed']
  end

  def load_document_relationships
    rels_xml = read_docx_entry('word/_rels/document.xml.rels', required: false)
    return {} if rels_xml.blank?

    rels_doc = Nokogiri::XML(rels_xml)
    rels_doc.xpath('//rels:Relationship', NAMESPACE).each_with_object({}) do |node, map|
      relation_id = node['Id']
      target = node['Target']
      map[relation_id] = target if relation_id.present? && target.present?
    end
  end

  def upload_image_url(relationship_id)
    target = @document_relationships[relationship_id]
    return nil if target.blank?

    image_entry_path = resolve_image_entry_path(target)
    return nil if image_entry_path.blank?

    image_binary = read_docx_entry(image_entry_path, required: false)
    return nil if image_binary.blank?

    filename = File.basename(image_entry_path)
    blob = ActiveStorage::Blob.create_and_upload!(
      io: StringIO.new(image_binary),
      filename: filename,
      content_type: Marcel::MimeType.for(StringIO.new(image_binary), name: filename)
    )

    Rails.application.routes.url_helpers.url_for(blob)
  end

  def resolve_image_entry_path(target)
    normalized_target = target.to_s.tr('\\', '/').sub(%r{\A/+}, '')
    return nil if normalized_target.blank?
    return nil if normalized_target.split('/').include?('..')

    return normalized_target if normalized_target.start_with?('word/')

    File.join('word', normalized_target)
  end

  def read_docx_entry(path, required: true)
    entry = @zip.find_entry(path)
    raise Error, "DOCX is missing #{path}" if entry.blank? && required
    return nil if entry.blank?

    entry.get_input_stream.read
  end

  def parse_qa_pairs(text)
    split_blocks(text).filter_map { |block| parse_block(block) }
  end

  def split_blocks(text)
    blocks = []
    current = []

    text.to_s.each_line do |line|
      if line.strip == @separator
        blocks << current.join("\n").strip
        current = []
      else
        current << line.chomp
      end
    end

    blocks << current.join("\n").strip if current.any?
    blocks.reject(&:blank?)
  end

  def parse_block(block)
    parsed = {
      current_target: nil,
      question: [],
      answer: []
    }

    block.lines.map(&:chomp).each do |line|
      consume_line(parsed, line)
    end

    question = parsed[:question].join("\n").strip
    answer = parsed[:answer].join("\n").strip
    return nil if question.blank? || answer.blank?

    { question: question, answer: answer }
  end

  def consume_line(parsed, line)
    marker = detect_marker(line)
    if marker
      parsed[:current_target] = marker[:target]
      parsed[marker[:target]] << marker[:content] if marker[:content].present?
      return
    end

    target = parsed[:current_target]
    parsed[target] << line if target.present?
  end

  def detect_marker(line)
    stripped = line.strip

    question_marker = stripped.match(/\Aquestion\s*[:：]\s*(.*)\z/i)
    return { target: :question, content: question_marker[1] } if question_marker

    answer_marker = stripped.match(/\Aanswer\s*[:：]\s*(.*)\z/i)
    return { target: :answer, content: answer_marker[1] } if answer_marker

    nil
  end
end
