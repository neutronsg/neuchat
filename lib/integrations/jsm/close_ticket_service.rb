class Integrations::Jsm::CloseTicketService
  pattr_initialize [:conversation!]

  def perform
    return if hook.blank?
    return if issue_id_or_key.blank?
    return unless conversation.resolved?

    client.close_issue(issue_id_or_key)
  end

  private

  def hook
    @hook ||= conversation.account.hooks.enabled.find_by(app_id: 'jsm')
  end

  def client
    @client ||= Integrations::Jsm::Client.new(hook: hook)
  end

  def issue_id_or_key
    jsm_attributes['ticket_key'].presence || jsm_attributes['ticket_id'].presence
  end

  def jsm_attributes
    @jsm_attributes ||= conversation.additional_attributes.to_h['jsm'].to_h
  end
end
