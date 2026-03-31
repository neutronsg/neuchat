class Wechat::SendOnWechatService
  pattr_initialize [:message!]

  def perform
    # Skip processing if message is not outgoing or if it's from WeChat itself
    return if message.private? || message.activity? || !message.outgoing? || message.source_id.present?

    # Send the message via WeChat Customer Service API
    message_id = channel.send_message_on_wechat(message)

    if message_id
      message.update!(source_id: message_id.to_s)
    else
      Rails.logger.error "Failed to send WeChat message: #{message.id}"
      message.update!(status: :failed)
    end
  end

  private

  def channel
    @channel ||= message.conversation.inbox.channel
  end
end
