class Wechat::SendAttachmentsService
  pattr_initialize [:message!]

  def perform
    attachment_message_id = nil

    message.attachments.each do |attachment|
      attachment_message_id = process_attachment(attachment)
      break if attachment_message_id.nil?
    end

    attachment_message_id
  end

  private

  def process_attachment(attachment)
    case attachment.file_type
    when 'image'
      send_image_message(attachment)
    when 'audio'
      send_voice_message(attachment)
    when 'video'
      send_video_message(attachment)
    when 'file'
      send_file_message(attachment)
    when 'location'
      send_location_message(attachment)
    else
      send_text_message("📎 附件: #{attachment.file.filename}")
    end
  end

  def send_image_message(attachment)
    media_id = upload_media(attachment, 'image')
    return nil unless media_id

    send_media_message('image', media_id)
  end

  def send_voice_message(attachment)
    media_id = upload_media(attachment, 'voice')
    return nil unless media_id

    send_media_message('voice', media_id)
  end

  def send_video_message(attachment)
    media_id = upload_media(attachment, 'video')
    return nil unless media_id

    send_media_message('video', media_id, {
      title: attachment.file.filename.to_s,
      description: "视频文件"
    })
  end

  def send_file_message(attachment)
    # WeChat doesn't support arbitrary file types, send as text with download link
    download_url = attachment.download_url
    text = "📎 文件: #{attachment.file.filename}\n下载链接: #{download_url}"
    send_text_message(text)
  end

  def send_location_message(attachment)
    access_token = channel.get_access_token
    return nil unless access_token

    response = HTTParty.post("#{channel.wechat_api_url}/message/custom/send",
      query: { access_token: access_token },
      headers: { 'Content-Type' => 'application/json; charset=utf-8' },
      body: {
        touser: channel.openid(message),
        msgtype: 'text',
        text: {
          content: "📍 位置: #{attachment.fallback_title}\n纬度: #{attachment.coordinates_lat}\n经度: #{attachment.coordinates_long}"
        }
      }.to_json
    )

    handle_response(response)
  end

  def upload_media(attachment, media_type)
    access_token = channel.get_access_token
    return nil unless access_token

    # Create temporary file for upload
    temp_file = create_temp_file(attachment)

    begin
      response = HTTParty.post("#{channel.wechat_api_url}/media/upload",
        query: {
          access_token: access_token,
          type: media_type
        },
        body: {
          media: File.open(temp_file, 'rb')
        }
      )

      if response.success? && response.parsed_response['media_id']
        response.parsed_response['media_id']
      else
        Rails.logger.error "WeChat media upload failed: #{response.parsed_response}"
        nil
      end
    ensure
      File.delete(temp_file) if File.exist?(temp_file)
    end
  end

  def send_media_message(msg_type, media_id, extra_data = {})
    access_token = channel.get_access_token
    return nil unless access_token

    body = {
      touser: channel.openid(message),
      msgtype: msg_type,
      msg_type.to_sym => { media_id: media_id }.merge(extra_data)
    }

    response = HTTParty.post("#{channel.wechat_api_url}/message/custom/send",
      query: { access_token: access_token },
      headers: { 'Content-Type' => 'application/json; charset=utf-8' },
      body: body.to_json
    )

    handle_response(response)
  end

  def send_text_message(content)
    access_token = channel.get_access_token
    return nil unless access_token

    response = HTTParty.post("#{channel.wechat_api_url}/message/custom/send",
      query: { access_token: access_token },
      headers: { 'Content-Type' => 'application/json; charset=utf-8' },
      body: {
        touser: channel.openid(message),
        msgtype: 'text',
        text: { content: content }
      }.to_json
    )

    handle_response(response)
  end

  def create_temp_file(attachment)
    raw_data = attachment.file.download
    temp_dir = Rails.root.join('tmp/uploads')
    FileUtils.mkdir_p(temp_dir)

    temp_file_path = temp_dir.join("wechat_#{SecureRandom.hex(8)}_#{attachment.file.filename}")
    File.write(temp_file_path, raw_data, mode: 'wb')
    temp_file_path
  end

  def handle_response(response)
    channel.process_error(message, response)
    response.parsed_response['msgid'] if response.success?
  end

  def channel
    @channel ||= message.inbox.channel
  end
end
