# Only fixed enums and stable question IDs cross the Bot/NeuChat boundary.
class Conversations::BotOutcomeContract
  STATUSES = %w[answered confirmed_solved unresolved].freeze
  STAGES = %w[none offered declined accepted].freeze
  REASONS = %w[user_requested_support no_answer_found requires_other_person].freeze
  DESTINATIONS = %w[company_admin hr oca_support].freeze
  def self.validate!(data)
    object!(data, %w[categories enquiries escalation])
    categories!(data['categories'])
    enquiries!(data['enquiries'])
    escalation!(data['escalation'])
  end

  def self.object!(value, keys)
    raise ArgumentError, 'Invalid outcome object' unless value.is_a?(Hash) && value.keys.sort == keys.sort
  end

  def self.categories!(values)
    valid = values.is_a?(Array) && values.size <= 20 && values.uniq.size == values.size
    raise ArgumentError, 'Invalid categories' unless valid && (values - Conversations::BotOutcomeState::CATEGORIES).empty?
  end

  def self.enquiries!(values)
    raise ArgumentError, 'Invalid enquiries' unless values.is_a?(Array) && values.size <= 40

    values.each { |value| enquiry!(value) }
    raise ArgumentError, 'Duplicate enquiry' unless values.pluck('id').uniq.size == values.size
  end

  def self.enquiry!(value)
    object!(value, value.is_a?(Hash) && value.key?('evidence') ? %w[id status evidence] : %w[id status])
    enquiry_evidence!(value)

    valid_id = value['id'].is_a?(String) && value['id'].match?(/\Aq[1-9][0-9]{0,5}\z/)
    raise ArgumentError, 'Invalid enquiry' unless valid_id && STATUSES.include?(value['status'])
  end

  def self.enquiry_evidence!(value)
    return unless value.key?('evidence')

    raise ArgumentError, 'Invalid enquiry evidence' unless %w[current_reply previous_reply].include?(value['evidence'])
  end

  def self.escalation!(value)
    object!(value, %w[stage reason destination consentMessageId])
    raise ArgumentError, 'Invalid stage' unless STAGES.include?(value['stage'])

    if value['stage'] == 'none'
      raise ArgumentError, 'Invalid empty escalation' unless value.values_at('reason', 'destination', 'consentMessageId') == ['none', 'none', 0]

      return
    end
    route!(value)
  end

  def self.route!(value)
    raise ArgumentError, 'Invalid route' unless REASONS.include?(value['reason']) && DESTINATIONS.include?(value['destination'])

    consent = value['consentMessageId']
    valid = consent.is_a?(Integer) && (value['stage'] == 'accepted' ? consent.positive? : consent.zero?)
    raise ArgumentError, 'Invalid consent' unless valid
  end
end
