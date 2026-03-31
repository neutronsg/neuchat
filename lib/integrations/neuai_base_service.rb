class Integrations::NeuaiBaseService
  # gpt-4o-mini supports 128,000 tokens
  # 1 token is approx 4 characters
  # sticking with 120000 to be safe
  # 120000 * 4 = 480,000 characters (rounding off downwards to 400,000 to be safe)
  TOKEN_LIMIT = 400_000

  DIFY_WORKFLOW_API_PATH = '/workflows/run'.freeze
  ALLOWED_EVENT_NAMES = %w[rephrase summarize reply_suggestion fix_spelling_grammar make_friendly make_formal simplify
                           translate].freeze
  CACHEABLE_EVENTS = %w[summarize].freeze

  pattr_initialize [:hook!, :event!]

  def perform
    return nil unless valid_event_name?

    return value_from_cache if value_from_cache.present?

    response = send("#{event_name}_message")
    save_to_cache(response) if response.present?

    response
  end

  private

  def event_name
    event['name']
  end

  def cache_key
    return nil unless event_is_cacheable?

    return nil unless conversation

    # since the value from cache depends on the conversation last_activity_at, it will always be fresh
    format(::Redis::Alfred::NEUAI_CONVERSATION_KEY, event_name: event_name, conversation_id: conversation.id,
                                                    updated_at: conversation.last_activity_at.to_i)
  end

  def value_from_cache
    return nil unless event_is_cacheable?
    return nil if cache_key.blank?

    deserialize_cached_value(Redis::Alfred.get(cache_key))
  end

  def deserialize_cached_value(value)
    return nil if value.blank?

    JSON.parse(value, symbolize_names: true)
  rescue JSON::ParserError
    # If json parse failed, returning the value as is will fail too
    # since we access the keys as symbols down the line
    # So it's best to return nil
    nil
  end

  def save_to_cache(response)
    return nil unless event_is_cacheable?

    # Serialize to JSON
    # This makes parsing easy when response is a hash
    Redis::Alfred.setex(cache_key, response.to_json)
  end

  def conversation
    @conversation ||= hook.account.conversations.find_by(display_id: event['data']['conversation_display_id'])
  end

  def valid_event_name?
    # self.class::ALLOWED_EVENT_NAMES is way to access ALLOWED_EVENT_NAMES defined in the class hierarchy of the current object.
    # This ensures that if ALLOWED_EVENT_NAMES is updated elsewhere in it's ancestors, we access the latest value.
    self.class::ALLOWED_EVENT_NAMES.include?(event_name)
  end

  def event_is_cacheable?
    # self.class::CACHEABLE_EVENTS is way to access CACHEABLE_EVENTS defined in the class hierarchy of the current object.
    # This ensures that if CACHEABLE_EVENTS is updated elsewhere in it's ancestors, we access the latest value.
    self.class::CACHEABLE_EVENTS.include?(event_name)
  end

  def make_api_call(body)
    request_body = build_dify_request_body(body)

    Rails.logger.info("NeuAI API request: #{request_body.to_json}")
    response = HTTParty.post(workflow_api_url, headers: dify_headers, body: request_body.to_json)
    Rails.logger.info("NeuAI API response: #{response.body}")

    return error_response(error_message_from(response.parsed_response), response.code) unless response.success?

    response_from_dify(response)
  end

  def build_dify_request_body(body)
    payload = body.is_a?(String) ? JSON.parse(body) : body

    {
      inputs: {
        query: payload['query'] || payload['question'],
        action: payload.dig('overrideConfig', 'vars', 'action')
      }.compact,
      response_mode: 'blocking',
      user: dify_user
    }
  end

  def dify_user
    conversation_display_id = event.dig('data', 'conversation_display_id')
    return "conversation-#{conversation_display_id}" if conversation_display_id.present?

    "account-#{hook.account_id}"
  end

  def response_from_dify(response)
    parsed_response = JSON.parse(response.body)
    return workflow_failure_response(parsed_response) if workflow_failed?(parsed_response)

    { message: message_from(parsed_response) }
  rescue JSON::ParserError
    { message: nil }
  end

  def workflow_failed?(parsed_response)
    %w[failed stopped].include?(parsed_response.dig('data', 'status'))
  end

  def workflow_failure_response(parsed_response)
    message = parsed_response.dig('data', 'error').presence || 'Dify workflow execution failed'
    error_response(message, 422)
  end

  def workflow_api_url
    "#{hook.settings['neuai_url'].to_s.chomp('/')}#{DIFY_WORKFLOW_API_PATH}"
  end

  def dify_headers
    {
      'Content-Type' => 'application/json',
      'Authorization' => "Bearer #{hook.settings['api_key']}"
    }
  end

  def message_from(parsed_response)
    direct_message_from(parsed_response) || output_message_from(parsed_response)
  end

  def direct_message_from(parsed_response)
    find_string_value(parsed_response, %w[text message answer])
  end

  def output_message_from(parsed_response)
    outputs = parsed_response.dig('data', 'outputs')
    return nil unless outputs.is_a?(Hash)

    find_string_value(outputs, %w[text answer message result output]) ||
      outputs.values.find { |value| value.is_a?(String) && value.present? }
  end

  def find_string_value(hash, fields)
    fields.each do |field|
      value = hash[field]
      return value if value.is_a?(String) && value.present?
    end

    nil
  end

  def error_message_from(parsed_response)
    return 'Dify API request failed' unless parsed_response.is_a?(Hash)

    parsed_response.dig('error', 'message') || parsed_response['message'] || parsed_response['error'] || 'Dify API request failed'
  end

  def error_response(message, code)
    {
      error: {
        error: {
          message: message
        }
      },
      error_code: code
    }
  end
end
