class Integrations::Neuai::ContactNoteContextBuilder
  TOKEN_LIMIT = Integrations::NeuaiBaseService::TOKEN_LIMIT
  CONTACT_NOTES_LIMIT = TOKEN_LIMIT / 4

  def initialize(account:, contact_id:)
    @account = account
    @contact_id = contact_id
  end

  def build
    contact = @account.contacts.find(@contact_id)
    notes, notes_character_count = notes_within_limit(contact)
    messages = messages_within_limit(contact, notes_character_count)

    <<~CONTEXT
      Existing contact notes:
      #{notes.presence&.join("\n") || 'No existing contact notes'}

      Conversation history:
      #{messages.presence || 'No conversation history'}
    CONTEXT
  end

  private

  def notes_within_limit(contact)
    character_count = 0
    notes = []

    contact.notes.agent.order(created_at: :desc).includes(:user).each do |note|
      formatted_note = format_note(note)
      break if character_count + formatted_note.length > CONTACT_NOTES_LIMIT

      notes << formatted_note
      character_count += formatted_note.length
    end

    [notes, character_count]
  end

  def messages_within_limit(contact, start_from)
    character_count = start_from
    messages = []

    contact_messages(contact).each do |message|
      formatted_message = format_message(message)
      break if character_count + formatted_message.length > TOKEN_LIMIT

      messages.prepend(formatted_message)
      character_count += formatted_message.length
    end

    messages.join("\n")
  end

  def contact_messages(contact)
    Message.where(conversation_id: contact.conversations.select(:id))
           .where(message_type: [:incoming, :outgoing], private: false)
           .where.not(content: [nil, ''])
           .includes(:sender, conversation: :inbox)
           .reorder(id: :desc)
  end

  def format_note(note)
    note_type = note.neuai? ? 'AI-generated note' : 'Agent note'
    author = note.neuai? ? 'NeuAI' : (note.user&.name.presence || 'Agent')
    metadata = [
      "Created: #{format_timestamp(note.created_at)}",
      "Updated: #{format_timestamp(note.updated_at)}",
      "Type: #{note_type}",
      "Author: #{author}"
    ].join(' | ')

    "[#{metadata}] #{note.content}"
  end

  def format_message(message)
    direction = message.incoming? ? 'Incoming' : 'Outgoing'
    sender_role = message.incoming? ? 'Customer' : 'Agent'
    sender_name = message.sender&.name.presence || sender_role
    conversation_id = message.conversation.display_id
    metadata = [
      "Sent: #{format_timestamp(message.created_at, message.conversation.inbox.timezone)}",
      "Conversation: ##{conversation_id}",
      "Message ID: #{message.id}",
      "Direction: #{direction}",
      "Sender: #{sender_role} (#{sender_name})"
    ].join(' | ')

    "[#{metadata}] #{message.content}"
  end

  def format_timestamp(timestamp, zone_name = 'UTC')
    zone = ActiveSupport::TimeZone[zone_name] || ActiveSupport::TimeZone['UTC']
    "#{timestamp.in_time_zone(zone).iso8601} (#{zone.name})"
  end
end
