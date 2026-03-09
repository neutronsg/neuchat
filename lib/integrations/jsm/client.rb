require 'base64'

class Integrations::Jsm::Client
  class ApiError < StandardError; end

  pattr_initialize [:hook!]

  def close_issue(issue_id_or_key)
    response = HTTParty.post(
      "#{base_url}/rest/api/3/issue/#{issue_id_or_key}/transitions",
      headers: headers,
      body: {
        transition: {
          id: hook.settings['close_transition_id']
        }
      }.to_json
    )

    return true if response.code == 204

    raise ApiError, error_message(response)
  end

  private

  def base_url
    domain = hook.settings['domain'].to_s.sub(%r{\Ahttps?://}, '').sub(%r{/\z}, '')
    "https://#{domain}"
  end

  def headers
    {
      'Authorization' => "Basic #{encoded_credentials}",
      'Accept' => 'application/json',
      'Content-Type' => 'application/json'
    }
  end

  def encoded_credentials
    Base64.strict_encode64("#{hook.settings['email']}:#{hook.settings['api_token']}")
  end

  def error_message(response)
    parsed_response = response.parsed_response
    return 'JSM close ticket request failed' unless parsed_response.is_a?(Hash)

    parsed_response['errorMessages']&.join(', ') ||
      parsed_response.dig('errors')&.values&.join(', ') ||
      parsed_response['message'] ||
      'JSM close ticket request failed'
  end
end
