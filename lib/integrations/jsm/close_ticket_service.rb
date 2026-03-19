class Integrations::Jsm::CloseTicketService
  pattr_initialize [:conversation!]

  def perform
    return if hook.blank?
    return if jira_issue_id.blank?
    return unless conversation.resolved?

    response = client.update_and_resolve_issue(conversation, jira_issue_id: jira_issue_id)
    outputs = response.dig('data', 'outputs').to_h
    returned_issue_id = outputs['jira_issue_id'].presence

    raise Integrations::Jsm::Client::ApiError, 'JSM workflow returned empty jira_issue_id' if returned_issue_id.blank?

    persist_ticket_details(returned_issue_id, outputs['jira_issue_key'])
  end

  private

  def hook
    @hook ||= conversation.account.hooks.enabled.find_by(app_id: 'jsm')
  end

  def client
    @client ||= Integrations::Jsm::Client.new(hook: hook)
  end

  def jira_issue_id
    jsm_attributes['ticket_id'].presence || jsm_attributes['ticket_key'].presence
  end

  def jsm_attributes
    @jsm_attributes ||= conversation.additional_attributes.to_h['jsm'].to_h
  end

  def persist_ticket_details(issue_id, issue_key)
    updated_attributes = jsm_attributes.merge(
      'ticket_id' => issue_id,
      'ticket_key' => issue_key.presence || jsm_attributes['ticket_key']
    ).compact

    conversation.update_column(
      :additional_attributes,
      conversation.additional_attributes.to_h.merge('jsm' => updated_attributes)
    )
  end
end
