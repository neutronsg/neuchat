class Integrations::Jsm::CloseTicketJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    Integrations::Jsm::CloseTicketService.new(conversation: conversation).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation&.account).capture_exception
    Rails.logger.error("JSM close ticket failed for conversation #{conversation_id}: #{e.message}")
    raise e
  end
end
