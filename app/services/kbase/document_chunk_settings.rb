class Kbase::DocumentChunkSettings
  class Error < StandardError; end

  DEFAULT_SEPARATOR = "\n\n".freeze
  DEFAULT_MAX_TOKENS = 1024
  DEFAULT_CHUNK_OVERLAP = 50
  SUPPORTED_RULE_IDS = %w[remove_extra_spaces remove_urls_emails].freeze

  attr_reader :separator, :max_tokens, :chunk_overlap, :pre_processing_rules

  def self.default(separator: DEFAULT_SEPARATOR)
    new(
      separator: separator,
      max_tokens: DEFAULT_MAX_TOKENS,
      chunk_overlap: DEFAULT_CHUNK_OVERLAP,
      pre_processing_rules: {}
    )
  end

  def self.default_process_rule(separator: DEFAULT_SEPARATOR)
    default(separator: separator).to_process_rule
  end

  def self.from_payload(payload)
    data = payload.to_h.with_indifferent_access

    new(
      separator: decode_separator(data[:separator]),
      max_tokens: parse_integer(data[:max_tokens], 'max_tokens'),
      chunk_overlap: parse_integer(data[:chunk_overlap], 'chunk_overlap'),
      pre_processing_rules: normalize_pre_processing_rules(data[:pre_processing_rules])
    )
  end

  def self.from_dify(document_process_rule:, dataset_process_rule:)
    source_rule = document_process_rule.presence || dataset_process_rule.presence
    source = if document_process_rule.present?
               'document'
             elsif dataset_process_rule.present?
               'dataset'
             else
               'default'
             end

    return default.to_response(source: source) if source_rule.blank?

    data = source_rule.with_indifferent_access
    rules = data[:rules].to_h.with_indifferent_access
    mode = data[:mode].to_s

    return unsupported_response(source: source, mode: mode) if mode != 'custom'
    return unsupported_response(source: source, mode: mode) if rules[:parent_mode].present?
    return unsupported_response(source: source, mode: mode) if rules[:subchunk_segmentation].present?

    segmentation = rules[:segmentation].to_h.with_indifferent_access
    new(
      separator: segmentation[:separator],
      max_tokens: parse_integer(segmentation[:max_tokens], 'max_tokens'),
      chunk_overlap: parse_integer(segmentation[:chunk_overlap], 'chunk_overlap'),
      pre_processing_rules: normalize_pre_processing_rule_array(rules[:pre_processing_rules])
    ).to_response(source: source)
  rescue Error
    unsupported_response(source: source, mode: mode.presence || 'unknown')
  end

  def initialize(separator:, max_tokens:, chunk_overlap:, pre_processing_rules:)
    @separator = separator.nil? ? DEFAULT_SEPARATOR : separator
    @max_tokens = max_tokens
    @chunk_overlap = chunk_overlap
    @pre_processing_rules = self.class.send(:normalize_pre_processing_rules, pre_processing_rules)

    validate!
  end

  def to_process_rule
    {
      mode: 'custom',
      rules: {
        pre_processing_rules: pre_processing_rule_list,
        segmentation: {
          separator: separator,
          max_tokens: max_tokens,
          chunk_overlap: chunk_overlap
        }
      }
    }
  end

  def to_response(source:)
    {
      source: source,
      mode: 'custom',
      separator: separator,
      max_tokens: max_tokens,
      chunk_overlap: chunk_overlap,
      pre_processing_rules: normalized_pre_processing_rule_hash,
      editable: true
    }
  end

  private

  def validate!
    raise Error, 'separator is required' if separator.nil? || separator == ''
    raise Error, 'max_tokens must be greater than 0' if max_tokens <= 0
    raise Error, 'chunk_overlap must be greater than or equal to 0' if chunk_overlap.negative?
    raise Error, 'chunk_overlap must be less than or equal to max_tokens' if chunk_overlap > max_tokens
  end

  def normalized_pre_processing_rule_hash
    SUPPORTED_RULE_IDS.index_with { |rule_id| ActiveModel::Type::Boolean.new.cast(pre_processing_rules[rule_id]) }
  end

  def pre_processing_rule_list
    normalized_pre_processing_rule_hash.map do |rule_id, enabled|
      { id: rule_id, enabled: enabled }
    end
  end

  def self.parse_integer(value, field)
    Integer(value)
  rescue ArgumentError, TypeError
    raise Error, "#{field} must be an integer"
  end

  def self.normalize_pre_processing_rule_array(rules)
    Array(rules).each_with_object({}) do |rule, hash|
      data = rule.to_h.with_indifferent_access
      next unless SUPPORTED_RULE_IDS.include?(data[:id].to_s)

      hash[data[:id].to_s] = ActiveModel::Type::Boolean.new.cast(data[:enabled])
    end
  end

  def self.normalize_pre_processing_rules(rules)
    data = (rules || {}).to_h.with_indifferent_access

    unsupported_rule_ids = data.keys.map(&:to_s) - SUPPORTED_RULE_IDS
    raise Error, 'pre_processing_rules contains unsupported keys' if unsupported_rule_ids.any?

    SUPPORTED_RULE_IDS.index_with do |rule_id|
      ActiveModel::Type::Boolean.new.cast(data[rule_id])
    end
  rescue NoMethodError
    raise Error, 'pre_processing_rules must be an object'
  end

  def self.decode_separator(separator)
    value = separator.presence || DEFAULT_SEPARATOR

    value
      .gsub('\\r', "\r")
      .gsub('\\n', "\n")
      .gsub('\\t', "\t")
  end

  def self.unsupported_response(source:, mode:)
    {
      source: source,
      mode: mode.presence || 'unknown',
      editable: false,
      reason: 'unsupported_mode'
    }
  end
end
