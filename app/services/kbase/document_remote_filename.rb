class Kbase::DocumentRemoteFilename
  PREFIX = 'neuchat-kb'.freeze
  FALLBACK_FILENAME = 'upload'.freeze

  def self.build(knowledge_base_id:, original_filename:)
    filename = File.basename(original_filename.to_s).presence || FALLBACK_FILENAME
    "#{PREFIX}-#{knowledge_base_id}--#{filename}"
  end
end
