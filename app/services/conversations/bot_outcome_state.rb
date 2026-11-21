# Called within the message transaction, with the conversation row locked.
class Conversations::BotOutcomeState
  CATEGORIES = ['Sign-up/login', 'Learning related', 'CMS portal', 'LMS portal', 'Other apps', 'Data migration', 'App download',
                'Suggestions', 'MAX points related', 'Notifications related', 'Rewards', 'CR points related', 'Learning Terminal related',
                'Awards Terminal related', 'Allocation management', 'Reports', 'Community Terminal related', 'Leaderboard', 'Home page',
                'Android version', 'Dashboards', 'Airport 101', 'QR code scanner', 'Others'].freeze
  REASONS = %w[user_requested_support no_answer_found requires_other_person].freeze
  DESTINATIONS = %w[company_admin hr oca_support].freeze

  def initialize(conversation)
    @conversation = conversation
  end

  def on_message(message)
    return if message.private? || message.activity?

    state = @conversation.bot_conversation_outcome
    if message.incoming?
      state&.update!(all_solved: false, closed_at: nil)
      return
    end
    attrs = message.content_attributes
    return unless authenticated?(message, attrs)

    apply_reply(message, attrs, state)
  end

  def apply_reply(message, attrs, state)
    trigger = current_trigger(attrs)
    return unless trigger

    state ||= @conversation.build_bot_conversation_outcome(account_id: @conversation.account_id)
    return if trigger.id <= state.evaluated_input_id

    apply_outcome(state, attrs['bot_outcome'], trigger, message)
    restored = restore_command_outcome(state, trigger, attrs)
    state.last_reply_assessed = attrs['bot_outcome'].present? || restored == true
    state.all_solved &&= latest_input?(trigger) && delivery_evidence_valid?(state)
    state.evaluated_input_id = trigger.id
    state.last_message_id = message.id
    state.save!
  end

  def restore_command_outcome(state, trigger, attrs)
    return unless attrs['bot_close_reason'] == 'command' && trigger.attachments.empty?
    return unless trigger.content.to_s.strip.casecmp('End Conversation').zero?

    return unless previous_answer_current?(state, trigger)

    state.all_solved = state.enquiries.present? && state.enquiries.all? { |e| e['status'] != 'unresolved' }
    true
  end

  def previous_answer_current?(state, trigger)
    previous_input = @conversation.messages.incoming.where(private: false).where('id < ?', trigger.id).maximum(:id)
    return false unless state.last_reply_assessed && previous_input == state.evaluated_input_id

    @conversation.messages.where(id: state.last_message_id).where.not(status: :failed).exists?
  end

  def current_trigger(attrs)
    @conversation.messages.incoming.find_by(private: false, id: attrs['bot_trigger_message_id'])
  end

  def latest_input?(trigger)
    trigger.id == @conversation.messages.incoming.where(private: false).maximum(:id)
  end

  def apply_outcome(state, outcome, trigger, message)
    state.all_solved = false
    return if outcome.blank?

    Conversations::BotOutcomeContract.validate!(outcome, account: @conversation.account)
    bind_delivery_evidence(state, outcome.fetch('enquiries'), message.id)
    merge_enquiries(state, outcome.fetch('enquiries').map { |enquiry| enquiry.slice('id', 'status') })
    state.categories = (state.categories + outcome.fetch('categories')).uniq
    record_escalation(state, outcome.fetch('escalation'), trigger, message)
    Conversations::BotCategoryLabels.sync!(@conversation, state.categories)
  end

  def bind_delivery_evidence(state, enquiries, message_id)
    dependencies = state.enquiry_message_ids.dup
    enquiries.each do |enquiry|
      previous = state.enquiries.find { |item| item['id'] == enquiry['id'] }
      # Legacy replies cannot distinguish a carried status from an independent re-answer.
      if carried_enquiry?(enquiry, previous)
        raise ArgumentError, 'Invalid carried enquiry' unless previous&.fetch('status') == enquiry['status']
      else
        dependencies[enquiry.fetch('id')] = message_id
      end
    end
    state.enquiry_message_ids = dependencies
  end

  def carried_enquiry?(enquiry, previous)
    enquiry['evidence'] == 'previous_reply' ||
      (enquiry['evidence'].nil? && previous&.fetch('status') == enquiry['status'])
  end

  def merge_enquiries(state, enquiries)
    previous = state.enquiries.reject { |e| enquiries.any? { |n| n['id'] == e['id'] } }
    state.enquiries = previous + enquiries
    state.all_solved = state.enquiries.present? && state.enquiries.all? { |e| e['status'] != 'unresolved' }
  end

  def delivery_evidence_valid?(state)
    ids = state.enquiry_message_ids.values.uniq
    complete = state.enquiries.all? { |enquiry| state.enquiry_message_ids.key?(enquiry['id']) }
    complete && ids.present? && @conversation.messages.where(id: ids).where.not(status: :failed).count == ids.size
  end

  private

  def authenticated?(message, attrs)
    return false unless message.outgoing? && !message.failed? && message.sender_type == 'AgentBot'

    attrs['bot_outcome_authorized'] == true && attrs['bot_outcome_protocol'] == 1 && bound_bot?(message.sender_id)
  end

  def bound_bot?(sender_id)
    binding = @conversation.inbox.agent_bot_inbox
    binding.present? && binding.active? && binding.agent_bot_id == sender_id
  end

  def record_escalation(state, escalation, trigger, message)
    return unless escalation['stage'] == 'accepted'

    consent_id = escalation.fetch('consentMessageId')
    unless consent_id <= trigger.id && @conversation.messages.incoming.exists?(private: false, id: consent_id)
      raise ArgumentError, 'Invalid consent evidence'
    end

    entry = escalation.merge('message_id' => message.id, 'at' => message.created_at.iso8601)
    unless state.escalations.any? do |e|
      e.values_at('consentMessageId', 'destination', 'reason') == entry.values_at('consentMessageId', 'destination', 'reason')
    end
      state.escalations = state.escalations + [entry]
    end
    state.escalated_at ||= message.created_at
  end
end
