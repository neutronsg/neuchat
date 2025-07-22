class Integrations::Neuai::ProcessorService < Integrations::NeuaiBaseService
  def reply_suggestion_message
    make_api_call(reply_suggestion_body)
  end

  def summarize_message
    make_api_call(summarize_body)
  end

  def label_suggestion_message
    make_api_call(label_suggestion_body)
  end

  def rephrase_message
    make_api_call(simple_message_body('rephrase'))
  end

  def fix_spelling_grammar_message
    make_api_call(simple_message_body('fix_spelling_grammar'))
  end

  def shorten_message
    make_api_call(simple_message_body('shorten'))
  end

  def expand_message
    make_api_call(simple_message_body('expand'))
  end

  def make_friendly_message
    make_api_call(simple_message_body('make_friendly'))
  end

  def make_formal_message
    make_api_call(simple_message_body('make_formal'))
  end

  def simplify_message
    make_api_call(simple_message_body('simplify'))
  end

  def translate_message
    # NeuAI agent已经写好prompt，只需要传递消息和历史消息
    make_api_call(translate_body)
  end

  private

  def simple_message_body(action)
    # FlowiseAI API format - agent已经包含prompt，只传递消息内容
    {
      question: event['data']['content'],
      streaming: false,
      overrideConfig: {
        vars: {
          action: action
        }
      }
    }.to_json
  end

  def conversation_messages(in_array_format: false)
    messages = init_messages_body(in_array_format)

    add_messages_until_token_limit(conversation, messages, in_array_format)
  end

  def add_messages_until_token_limit(conversation, messages, in_array_format, start_from = 0)
    character_count = start_from
    conversation.messages.where(message_type: [:incoming, :outgoing]).where(private: false).reorder('id desc').each do |message|
      character_count, message_added = add_message_if_within_limit(character_count, message, messages, in_array_format)
      break unless message_added
    end
    messages
  end

  def add_message_if_within_limit(character_count, message, messages, in_array_format)
    if valid_message?(message, character_count)
      add_message_to_list(message, messages, in_array_format)
      character_count += message.content.length
      [character_count, true]
    else
      [character_count, false]
    end
  end

  def valid_message?(message, character_count)
    message.content.present? && character_count + message.content.length <= TOKEN_LIMIT
  end

  def add_message_to_list(message, messages, in_array_format)
    formatted_message = format_message(message, in_array_format)
    messages.prepend(formatted_message)
  end

  def init_messages_body(in_array_format)
    in_array_format ? [] : ''
  end

  def format_message(message, in_array_format)
    in_array_format ? format_message_in_array(message) : format_message_in_string(message)
  end

  def format_message_in_array(message)
    { role: (message.incoming? ? 'userMessage' : 'apiMessage'), content: message.content }
  end

  def format_message_in_string(message)
    sender_type = message.incoming? ? 'Customer' : 'Agent'
    "#{sender_type}: #{message.content}\n"
  end

  def summarize_body
    {
      question: conversation_messages(in_array_format: false),
      streaming: false,
      overrideConfig: {
        vars: {
          action: 'summarize'
        }
      }
    }.to_json
  end

  def reply_suggestion_body
    {
      question: conversation_messages(in_array_format: false),
      streaming: false,
      overrideConfig: {
        vars: {
          action: 'reply_suggestion'
        }
      }
    }.to_json
  end

  def label_suggestion_body
    {
      question: conversation_messages(in_array_format: false),
      streaming: false,
      overrideConfig: {
        vars: {
          action: 'label_suggestion'
        }
      }
    }.to_json
  end

  def translate_body
    str = "Chat History:\n #{conversation_messages(in_array_format: false)}"
    str += "\nProposed Agent Response:\n #{event['data']['content']}"
    {
      question: str,
      streaming: false,
      overrideConfig: {
        vars: {
          action: 'translate'
        }
      }
    }.to_json
  end
end

Integrations::Neuai::ProcessorService.prepend_mod_with('Integrations::NeuaiProcessorService')
