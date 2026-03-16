class Integrations::Jsm::CreateTicketService
  pattr_initialize [:conversation!]

  def perform
    return if hook.blank?
    return if linked_ticket?

    response = client.create_issue(conversation)
    outputs = response.dig('data', 'outputs').to_h
    issue_id = outputs['jira_issue_id'].presence

    raise Integrations::Jsm::Client::ApiError, 'JSM workflow returned empty jira_issue_id' if issue_id.blank?

    persist_ticket_details(issue_id, outputs['jira_issue_key'])
  end

  private

  def hook
    @hook ||= conversation.account.hooks.enabled.find_by(app_id: 'jsm')
  end

  def client
    @client ||= Integrations::Jsm::Client.new(hook: hook)
  end

  def linked_ticket?
    conversation.additional_attributes.to_h.dig('jsm', 'ticket_id').present? ||
      conversation.additional_attributes.to_h.dig('jsm', 'ticket_key').present?
  end

  def persist_ticket_details(issue_id, issue_key)
    jsm_attributes = conversation.additional_attributes.to_h['jsm'].to_h.merge(
      'ticket_id' => issue_id,
      'ticket_key' => issue_key.presence
    ).compact

    conversation.update_column(
      :additional_attributes,
      conversation.additional_attributes.to_h.merge('jsm' => jsm_attributes)
    )
  end
end
