class Integrations::Jsm::Client
  WORKFLOW_API_URL = 'https://neuai.neutron.sg/v1/workflows/run'.freeze
  class ApiError < StandardError; end

  pattr_initialize [:hook!]

  def create_issue(conversation)
    run_workflow(
      conversation: conversation,
      action: 'create_issue'
    )
  end

  def update_and_resolve_issue(conversation, jira_issue_id:)
    run_workflow(
      conversation: conversation,
      action: 'update_and_resolve_issue',
      jira_issue_id: jira_issue_id
    )
  end

  private

  def run_workflow(conversation:, action:, jira_issue_id: nil)
    response = HTTParty.post(
      WORKFLOW_API_URL,
      headers: headers,
      body: request_body(conversation, action, jira_issue_id).to_json
    )

    parsed_response = JSON.parse(response.body)

    raise ApiError, error_message(parsed_response) unless response.success?
    raise ApiError, workflow_error_message(parsed_response) if workflow_failed?(parsed_response)

    parsed_response
  rescue JSON::ParserError => e
    raise ApiError, "Invalid JSM workflow response: #{e.message}"
  end

  def headers
    {
      'Authorization' => "Bearer #{hook.settings['neuai_workflow_api_key']}",
      'Content-Type' => 'application/json',
      'Accept' => 'application/json'
    }
  end

  def request_body(conversation, action, jira_issue_id)
    {
      inputs: workflow_inputs(conversation, action, jira_issue_id),
      response_mode: 'blocking',
      user: workflow_user(conversation)
    }
  end

  def workflow_inputs(conversation, action, jira_issue_id)
    {
      chat_history: Integrations::Jsm::ChatHistoryFormatter.new(conversation: conversation).format,
      neuchat_conversation_id: conversation.id,
      jira_cloud_id: hook.settings['jira_cloud_id'],
      jira_project_key: hook.settings['jira_project_key'],
      action: action,
      neuchat_channel_name: conversation.inbox.inbox_type,
      jira_issue_id: jira_issue_id.presence
    }.compact
  end

  def workflow_user(conversation)
    "conversation-#{conversation.id}"
  end

  def workflow_failed?(parsed_response)
    %w[failed stopped].include?(parsed_response.dig('data', 'status'))
  end

  def workflow_error_message(parsed_response)
    parsed_response.dig('data', 'error').presence || 'JSM workflow execution failed'
  end

  def error_message(parsed_response)
    return 'JSM workflow request failed' unless parsed_response.is_a?(Hash)

    parsed_response.dig('error', 'message') ||
      parsed_response['message'] ||
      parsed_response['error'] ||
      'JSM workflow request failed'
  end
end
