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
      Generate one concise CRM note about this contact from the context below.
      Do not repeat information already captured in the existing notes.
      Only include facts supported by the context. Return the note text only.

      Existing contact notes:
      #{notes.presence&.join("\n") || 'No existing notes'}

      Conversation history:
      #{messages.presence || 'No conversation history'}
    CONTEXT
  end

  private

  def notes_within_limit(contact)
    character_count = 0
    notes = []

    contact.notes.latest.each do |note|
      formatted_note = "[#{note.neuai? ? 'Existing AI note' : 'Agent note'}] #{note.content}"
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
      break if character_count + message.content.length > TOKEN_LIMIT

      messages.prepend(format_message(message))
      character_count += message.content.length
    end

    messages.join("\n")
  end

  def contact_messages(contact)
    Message.where(conversation_id: contact.conversations.select(:id))
           .where(message_type: [:incoming, :outgoing], private: false)
           .where.not(content: [nil, ''])
           .reorder(id: :desc)
  end

  def format_message(message)
    sender = message.incoming? ? 'Customer' : 'Agent'
    "#{sender}: #{message.content}"
  end
end
