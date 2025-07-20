class Integrations::Neuai::ProcessorService < Integrations::NeuaiBaseService
  AGENT_INSTRUCTION = 'You are a helpful support agent.'.freeze
  LANGUAGE_INSTRUCTION = 'Ensure that the reply should be in user language.'.freeze

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
    make_api_call(build_api_call_body("#{AGENT_INSTRUCTION} Please rephrase the following response. " \
                                      "#{LANGUAGE_INSTRUCTION}", event['data']['content'], 'rephrase'))
  end

  def fix_spelling_grammar_message
    make_api_call(build_api_call_body("#{AGENT_INSTRUCTION} Please fix the spelling and grammar of the following response. " \
                                      "#{LANGUAGE_INSTRUCTION}", event['data']['content'], 'fix_spelling_grammar'))
  end

  def shorten_message
    make_api_call(build_api_call_body("#{AGENT_INSTRUCTION} Please shorten the following response. " \
                                      "#{LANGUAGE_INSTRUCTION}", event['data']['content'], 'shorten'))
  end

  def expand_message
    make_api_call(build_api_call_body("#{AGENT_INSTRUCTION} Please expand the following response. " \
                                      "#{LANGUAGE_INSTRUCTION}", event['data']['content'], 'expand'))
  end

  def make_friendly_message
    make_api_call(build_api_call_body("#{AGENT_INSTRUCTION} Please make the following response more friendly. " \
                                      "#{LANGUAGE_INSTRUCTION}", event['data']['content'], 'make_friendly'))
  end

  def make_formal_message
    make_api_call(build_api_call_body("#{AGENT_INSTRUCTION} Please make the following response more formal. " \
                                      "#{LANGUAGE_INSTRUCTION}", event['data']['content'], 'make_formal'))
  end

  def simplify_message
    make_api_call(build_api_call_body("#{AGENT_INSTRUCTION} Please simplify the following response. " \
                                      "#{LANGUAGE_INSTRUCTION}", event['data']['content'], 'simplify'))
  end

  def translate_message
    # NeuAI agent已经写好prompt，只需要传递消息和历史消息
    make_api_call(translate_body)
  end

  private

  def prompt_from_file(file_name, enterprise: false)
    path = enterprise ? 'enterprise/lib/enterprise/integrations/neuai_prompts' : 'lib/integrations/neuai/neuai_prompts'
    Rails.root.join(path, "#{file_name}.txt").read
  end

  def build_api_call_body(system_content, user_content = event['data']['content'], action = nil)
    # FlowiseAI API format
    {
      question: "#{system_content}\n\n#{user_content}",
      streaming: false,
      overrideConfig: {
        sessionId: "conversation_#{conversation.id}",
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
    { role: (message.incoming? ? 'user' : 'assistant'), content: message.content }
  end

  def format_message_in_string(message)
    sender_type = message.incoming? ? 'Customer' : 'Agent'
    "#{sender_type} #{message.sender&.name} : #{message.content}\n"
  end

  def summarize_body
    # FlowiseAI API format for conversation-level operation
    {
      question: "#{prompt_from_file('summary', enterprise: false)}\n\n#{conversation_messages}",
      streaming: false,
      overrideConfig: {
        sessionId: "conversation_#{conversation.id}",
        vars: {
          action: 'summarize'
        }
      }
    }.to_json
  end

  def reply_suggestion_body
    # FlowiseAI API format for conversation-level operation
    {
      question: "#{prompt_from_file('reply', enterprise: false)}\n\n#{conversation_messages}",
      streaming: false,
      overrideConfig: {
        sessionId: "conversation_#{conversation.id}",
        vars: {
          action: 'reply_suggestion'
        }
      }
    }.to_json
  end

  def label_suggestion_body
    # FlowiseAI API format for label suggestion (enterprise feature)
    {
      question: "Based on the following conversation, suggest relevant labels:\n\n#{conversation_messages}",
      streaming: false,
      overrideConfig: {
        sessionId: "conversation_#{conversation.id}",
        vars: {
          action: 'label_suggestion'
        }
      }
    }.to_json
  end

  def translate_body
    # FlowiseAI API format for translation - 传递当前消息和历史消息
    {
      question: "Current message: #{event['data']['content']}\n\nConversation history:\n#{conversation_messages}",
      streaming: false,
      overrideConfig: {
        sessionId: "conversation_#{conversation.id}",
        vars: {
          action: 'translate'
        }
      }
    }.to_json
  end
end

Integrations::Neuai::ProcessorService.prepend_mod_with('Integrations::NeuaiProcessorService')
