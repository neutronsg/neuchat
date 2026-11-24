require 'digest'

class BotSafetyReviews::Evidence
  UNAVAILABLE_OUTPUTS = %w[block masked].freeze
  VALID_DECISIONS = %w[allow block masked].freeze

  def self.call(run, message)
    audit = BotSafetyReviews::Client.call(run.account_id, '/internal/safety/evidence',
                                          { conversation: message.conversation.display_id, message: message.id }, post: false)
    audit = at_cutoff(audit, run.cutoff_at)
    transcript = transcript_for(run, message, audit)
    manifest = { messages: transcript.map { |m| { id: m[:id], hash: Digest::SHA256.hexdigest(m.to_json) } },
                 audit_hash: Digest::SHA256.hexdigest(audit.to_json) }
    { target_message_id: message.id, transcript: transcript, audit: audit, manifest: manifest }
  end

  def self.transcript_for(run, message, audit = {})
    reply_ids = audit.fetch('records', []).select { |r| r['kind'] == 'reply.result' }.filter_map { |r| r.dig('payload', 'messageId') }
    messages = run.account.messages.where(conversation_id: message.conversation_id, private: false)
                  .where('id <= ? AND created_at <= ?', run.high_water_id, run.cutoff_at)
                  .where('id <= ? OR content_attributes ->> ? = ? OR id IN (?)', message.id, 'bot_trigger_message_id', message.id.to_s, reply_ids)
                  .order(:id).limit(501).includes(:attachments).to_a
    raise ArgumentError, 'Conversation exceeds evidence limit' if messages.length > 500

    messages.map { |m| message_record(m) }
  end

  def self.message_record(message)
    { id: message.id, role: message.message_type, content: message.content, status: message.status, created_at: message.created_at.iso8601,
      trigger_id: message.content_attributes['bot_trigger_message_id'], attachments: message.attachments.map { |a| { id: a.id, type: a.file_type } } }
  end

  def self.each_object(value, &)
    case value
    when Hash
      yield value
      value.each_value { |v| each_object(v, &) }
    when Array then value.each { |v| each_object(v, &) }
    end
  end

  def self.at_cutoff(audit, cutoff)
    records = audit.fetch('records').select { |r| Time.iso8601(r.fetch('created_at')) <= cutoff }
    events = audit.fetch('events').select { |r| Time.iso8601(r.fetch('created_at')) <= cutoff }
    hashes = []
    each_object(records) { |v| hashes << v['auditBlob'] if v['auditBlob'] }
    blobs = audit.fetch('blobs', {}).slice(*hashes)
    audit.merge('records' => records, 'events' => events, 'blobs' => blobs, 'missingBlobs' => hashes.uniq - blobs.keys)
  end

  def self.complete?(evidence)
    audit = evidence.fetch(:audit)
    records = audit.fetch('records')
    return false unless available_records?(audit, records)
    return false unless exact_records?(records)
    return false unless references_valid?(records, evidence.fetch(:transcript))
    return false unless replies_valid?(records, evidence.fetch(:transcript))

    records.group_by { |r| r['request_id'] }.values.all? { |request| request_complete?(request, audit.fetch('events')) }
  end

  def self.available_records?(audit, records)
    audit.fetch('missingBlobs').empty? && records.present? && !original_output_unavailable?(audit.fetch('events'))
  end

  def self.original_output_unavailable?(events)
    events.any? { |e| e['provider'] == 'aws' && e['stage'] == 'output' && UNAVAILABLE_OUTPUTS.include?(e['status']) }
  end

  def self.request_complete?(request, events)
    ordered = request.sort_by { |r| r['sequence'] }
    kinds = ordered.pluck('kind')
    return false unless terminal_sequence?(kinds, ordered)

    request.select { |r| r['kind'] == 'plan' }.all? do |plan|
      plan_complete?(plan, events)
    end
  end

  def self.plan_complete?(plan, events)
    matching = events.select { |e| e['attempt_id'] == plan['attempt_id'] }
    (plan.dig('payload', 'expectedChecks') || []).all? { |check| checked_or_prevented?(check, matching) }
  end

  def self.checked_or_prevented?(check, events)
    provider, stage = check.split('.')
    observed = events.any? { |e| e['provider'] == provider && e['stage'] == stage && VALID_DECISIONS.include?(e['status']) }
    # Only a real input block makes subsequent output review unnecessary.
    stopped = stage == 'output' && input_blocked?(events)
    observed || stopped
  end

  def self.exact_records?(records)
    records.all? { |r| exact_record?(r) }
  end

  def self.exact_record?(record)
    record.dig('payload', 'evidenceStatus').blank? && !record.dig('payload', 'evidenceSanitized')
  end

  def self.terminal_sequence?(kinds, ordered)
    kinds.first == 'received' && kinds.include?('finished') && kinds.exclude?('failed') && ordered.pluck('sequence') == (0...ordered.length).to_a
  end

  def self.input_blocked?(events)
    events.any? { |e| e['enforced'] && e['status'] == 'block' && e['stage'] == 'input' }
  end

  def self.replies_valid?(records, transcript)
    sources = transcript.index_by { |m| m[:id] }
    records.select { |r| r['kind'] == 'reply.result' }.all? do |record|
      reply = record.fetch('payload')
      source = sources[reply['messageId']]
      source && Digest::SHA256.hexdigest(source[:content].to_s) == reply['contentHash']
    end
  end

  def self.references_valid?(records, transcript)
    sources = transcript.index_by { |m| m[:id] }
    valid = true
    each_object(records) { |value| valid = false unless reference_object_valid?(value, sources) }
    valid
  end

  def self.turn_valid?(turn, sources)
    return false unless %w[single user_group assistant_join].include?(turn['recipe'] || 'single')

    parts = turn['references'].map { |ref| source_part(ref, sources) }
    return false if parts.any?(&:nil?)

    text = turn['recipe'] == 'user_group' ? JSON.generate({ userMessages: parts }) : parts.pluck(:text).join("\n\n")
    Digest::SHA256.hexdigest(text) == turn['hash']
  end

  def self.reference_object_valid?(value, sources)
    return false if value['images'] == 'not_archived' || value['evidenceStatus'].present?
    return true unless value['references']
    return turn_valid?(value, sources) if value['hash']

    value['references'].all? { |ref| source_part(ref, sources) }
  end

  def self.source_part(ref, sources)
    source = sources[ref['id']]
    return unless source && Digest::SHA256.hexdigest(source[:content].to_s) == ref['hash']

    text = js_trim(source[:content].to_s)
    suffix = ref['stripSuffix']
    text = js_trim(text.delete_suffix(suffix)) if suffix.is_a?(String) && text.end_with?(suffix)
    { messageId: ref['id'], text: text }
  end

  def self.js_trim(text)
    text.gsub(/\A[\p{Space}\uFEFF]+|[\p{Space}\uFEFF]+\z/, '')
  end
end
