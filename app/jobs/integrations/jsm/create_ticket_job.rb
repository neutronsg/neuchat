class Integrations::Jsm::CreateTicketJob < ApplicationJob
  queue_as :default
  retry_on Integrations::Jsm::Client::ApiError, wait: 1.minute, attempts: 3

  def perform(conversation_id)
    conversation = Conversation.find_by(id: conversation_id)
    return if conversation.blank?

    Integrations::Jsm::CreateTicketService.new(conversation: conversation).perform
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: conversation&.account).capture_exception
    Rails.logger.error("JSM create ticket failed for conversation #{conversation_id}: #{e.message}")
    raise e
  end
end
