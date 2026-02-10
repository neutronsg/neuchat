require 'nokogiri'
require 'down'
require 'stringio'
require 'tempfile'
require 'uri'
require 'zip'

# rubocop:disable Metrics/ClassLength
class Kbase::QaDocxBuilder
  WORD_NAMESPACE = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'.freeze
  REL_NAMESPACE = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'.freeze
  DRAWING_NAMESPACE = 'http://schemas.openxmlformats.org/drawingml/2006/main'.freeze
  WORD_DRAWING_NAMESPACE = 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing'.freeze
  PIC_NAMESPACE = 'http://schemas.openxmlformats.org/drawingml/2006/picture'.freeze
  PACKAGE_REL_NAMESPACE = 'http://schemas.openxmlformats.org/package/2006/relationships'.freeze
  IMAGE_RELATIONSHIP_TYPE = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships/image'.freeze
  IMAGE_MARKDOWN_PATTERN = %r{!\[(?<alt>[^\]]*)\]\((?<url>https?://[^)\s]+)\)}i
  EMUS_PER_PIXEL = 9525
  DEFAULT_IMAGE_WIDTH_EMU = (320 * EMUS_PER_PIXEL).to_s
  DEFAULT_IMAGE_HEIGHT_EMU = (180 * EMUS_PER_PIXEL).to_s
  IMAGE_EXTENSION_TO_CONTENT_TYPE = {
    'png' => 'image/png',
    'jpg' => 'image/jpeg',
    'jpeg' => 'image/jpeg',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'tif' => 'image/tiff',
    'tiff' => 'image/tiff'
  }.freeze
  IMAGE_CONTENT_TYPE_TO_EXTENSION = {
    'image/png' => 'png',
    'image/jpeg' => 'jpg',
    'image/gif' => 'gif',
    'image/webp' => 'webp',
    'image/bmp' => 'bmp',
    'image/tiff' => 'tiff'
  }.freeze

  def initialize(qa_pairs, separator: '------')
    @qa_pairs = qa_pairs
    @separator = separator
    reset_embedded_images!
  end

  def build
    reset_embedded_images!
    docx_file = Tempfile.new(['qa-sync', '.docx'])
    docx_file.binmode
    docx_file.close

    built_document_xml = document_xml

    Zip::File.open(docx_file.path, create: true) do |zip|
      write_entry(zip, '[Content_Types].xml', content_types_xml)
      write_entry(zip, '_rels/.rels', root_relationships_xml)
      write_entry(zip, 'word/document.xml', built_document_xml)
      write_entry(zip, 'word/_rels/document.xml.rels', document_relationships_xml)
      write_embedded_images(zip)
    end

    docx_file
  rescue StandardError
    docx_file&.close!
    raise
  end

  private

  def reset_embedded_images!
    @embedded_images = []
    @embedded_images_by_url = {}
    @next_image_index = 1
  end

  def write_entry(zip, path, content)
    zip.get_output_stream(path) { |stream| stream.write(content) }
  end

  def write_embedded_images(zip)
    @embedded_images.each do |image|
      write_entry(zip, image[:path], image[:content])
    end
  end

  def qa_paragraph_fragments
    fragments = []
    @qa_pairs.each_with_index do |qa, index|
      fragments << [{ type: :text, value: 'Question:' }]
      multiline(qa[:question]).each { |line| fragments << fragments_for_line(line) }
      fragments << [{ type: :text, value: 'Answer:' }]
      multiline(qa[:answer]).each { |line| fragments << fragments_for_line(line) }
      fragments << [{ type: :text, value: @separator }] if index < @qa_pairs.length - 1
    end
    fragments
  end

  def multiline(value)
    value.to_s.split(/\r?\n/, -1).presence || ['']
  end

  def fragments_for_line(line)
    value = line.to_s
    fragments = []
    cursor = 0

    while (match = IMAGE_MARKDOWN_PATTERN.match(value, cursor))
      leading_text = value[cursor...match.begin(0)]
      fragments << { type: :text, value: leading_text } if leading_text.present?

      fragments << image_fragment_for_match(match)
      cursor = match.end(0)
    end

    trailing_text = value[cursor..]
    fragments << { type: :text, value: trailing_text } if trailing_text.present?
    fragments.presence || [{ type: :text, value: '' }]
  end

  def image_fragment_for_match(match)
    image_url = match[:url]
    embedded_image = embedded_image_for(image_url)
    return { type: :text, value: match[0] } if embedded_image.blank?

    {
      type: :image,
      relationship_id: embedded_image[:relationship_id],
      doc_pr_id: embedded_image[:doc_pr_id],
      name: embedded_image[:name]
    }
  end

  def embedded_image_for(image_url)
    return @embedded_images_by_url[image_url] if @embedded_images_by_url.key?(image_url)

    @embedded_images_by_url[image_url] = build_embedded_image(image_url)
  end

  def build_embedded_image(image_url)
    downloaded_file = Down.download(image_url)
    binary = downloaded_file.read
    return nil if binary.blank?

    embedded_image = build_embedded_image_payload(
      downloaded_file: downloaded_file,
      image_url: image_url,
      binary: binary
    )
    register_embedded_image(embedded_image)
  rescue StandardError => e
    Rails.logger.info(
      "[Kbase::QaDocxBuilder] Skip embedding image #{image_url}: #{e.class} #{e.message}"
    )
    nil
  ensure
    downloaded_file&.close! if downloaded_file.respond_to?(:close!)
  end

  def build_embedded_image_payload(downloaded_file:, image_url:, binary:)
    source_name = source_filename_for(downloaded_file, image_url)
    extension = normalized_extension_for(source_name, binary)
    media_name = "image#{@next_image_index}.#{extension}"

    {
      relationship_id: "rIdImage#{@next_image_index}",
      target: "media/#{media_name}",
      path: "word/media/#{media_name}",
      content: binary,
      extension: extension,
      content_type: content_type_for(extension, source_name, binary),
      doc_pr_id: @next_image_index,
      name: media_name
    }
  end

  def register_embedded_image(embedded_image)
    @next_image_index += 1
    @embedded_images << embedded_image
    embedded_image
  end

  def source_filename_for(downloaded_file, image_url)
    return downloaded_file.original_filename.to_s if downloaded_file.respond_to?(:original_filename) && downloaded_file.original_filename.present?

    parsed_url = URI.parse(image_url)
    filename = File.basename(parsed_url.path.to_s)
    filename.presence || 'image'
  rescue URI::InvalidURIError
    'image'
  end

  def normalized_extension_for(source_name, binary)
    extension = File.extname(source_name.to_s).delete('.').downcase
    extension = 'jpg' if extension == 'jpeg'
    return extension if IMAGE_EXTENSION_TO_CONTENT_TYPE.key?(extension)

    detected_content_type = Marcel::MimeType.for(StringIO.new(binary), name: source_name)
    IMAGE_CONTENT_TYPE_TO_EXTENSION[detected_content_type] || 'png'
  end

  def content_type_for(extension, source_name, binary)
    IMAGE_EXTENSION_TO_CONTENT_TYPE[extension] || Marcel::MimeType.for(StringIO.new(binary), name: source_name) || 'application/octet-stream'
  end

  def document_xml
    Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
      xml['w'].document(
        'xmlns:w' => WORD_NAMESPACE,
        'xmlns:r' => REL_NAMESPACE,
        'xmlns:a' => DRAWING_NAMESPACE,
        'xmlns:wp' => WORD_DRAWING_NAMESPACE,
        'xmlns:pic' => PIC_NAMESPACE
      ) do
        xml['w'].body do
          append_paragraphs(xml)
          append_section_properties(xml)
        end
      end
    end.to_xml
  end

  def append_paragraphs(xml)
    qa_paragraph_fragments.each do |paragraph_fragments|
      xml['w'].p do
        paragraph_fragments.each do |fragment|
          append_fragment(xml, fragment)
        end
      end
    end
  end

  def append_fragment(xml, fragment)
    case fragment[:type]
    when :image
      append_image_run(xml, fragment)
    else
      append_text_run(xml, fragment[:value])
    end
  end

  def append_text_run(xml, text)
    xml['w'].r do
      xml['w'].t(text.to_s, 'xml:space' => 'preserve')
    end
  end

  def append_image_run(xml, fragment)
    xml['w'].r do
      xml['w'].drawing do
        append_inline_image(xml, fragment)
      end
    end
  end

  def append_inline_image(xml, fragment)
    xml['wp'].inline('distT' => '0', 'distB' => '0', 'distL' => '0', 'distR' => '0') do
      append_inline_image_layout(xml, fragment)
      append_inline_image_graphic(xml, fragment)
    end
  end

  def append_inline_image_layout(xml, fragment)
    xml['wp'].extent('cx' => DEFAULT_IMAGE_WIDTH_EMU, 'cy' => DEFAULT_IMAGE_HEIGHT_EMU)
    xml['wp'].effectExtent('l' => '0', 't' => '0', 'r' => '0', 'b' => '0')
    xml['wp'].docPr('id' => fragment[:doc_pr_id].to_s, 'name' => fragment[:name])
    xml['wp'].cNvGraphicFramePr do
      xml['a'].graphicFrameLocks('noChangeAspect' => '1')
    end
  end

  def append_inline_image_graphic(xml, fragment)
    xml['a'].graphic do
      xml['a'].graphicData('uri' => 'http://schemas.openxmlformats.org/drawingml/2006/picture') do
        append_picture(xml, fragment)
      end
    end
  end

  def append_picture(xml, fragment)
    xml['pic'].pic do
      append_picture_metadata(xml, fragment)
      append_picture_fill(xml, fragment)
      append_picture_shape(xml)
    end
  end

  def append_picture_metadata(xml, fragment)
    xml['pic'].nvPicPr do
      xml['pic'].cNvPr('id' => '0', 'name' => fragment[:name])
      xml['pic'].cNvPicPr
    end
  end

  def append_picture_fill(xml, fragment)
    xml['pic'].blipFill do
      xml['a'].blip('r:embed' => fragment[:relationship_id])
      xml['a'].stretch { xml['a'].fillRect }
    end
  end

  def append_picture_shape(xml)
    xml['pic'].spPr do
      xml['a'].xfrm do
        xml['a'].off('x' => '0', 'y' => '0')
        xml['a'].ext('cx' => DEFAULT_IMAGE_WIDTH_EMU, 'cy' => DEFAULT_IMAGE_HEIGHT_EMU)
      end
      xml['a'].prstGeom('prst' => 'rect') { xml['a'].avLst }
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
        #{image_content_type_lines.join("\n    ")}
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
      </Types>
    XML
  end

  def image_content_type_lines
    image_content_types.map do |extension, content_type|
      %(<Default Extension="#{extension}" ContentType="#{content_type}"/>)
    end
  end

  def image_content_types
    @embedded_images.each_with_object({}) do |image, content_types|
      content_types[image[:extension]] ||= image[:content_type]
    end
  end

  def root_relationships_xml
    <<~XML
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <Relationships xmlns="#{PACKAGE_REL_NAMESPACE}">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
      </Relationships>
    XML
  end

  def document_relationships_xml
    Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
      xml.Relationships('xmlns' => PACKAGE_REL_NAMESPACE) do
        @embedded_images.each do |image|
          xml.Relationship(
            'Id' => image[:relationship_id],
            'Type' => IMAGE_RELATIONSHIP_TYPE,
            'Target' => image[:target]
          )
        end
      end
    end.to_xml
  end
end
# rubocop:enable Metrics/ClassLength
