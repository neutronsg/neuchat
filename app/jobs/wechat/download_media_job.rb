class Wechat::DownloadMediaJob < ApplicationJob
  queue_as :default

  def perform(message, media_id, media_type)
    access_token = message.inbox.channel.get_access_token
    return unless access_token

    begin
      # Download media from WeChat servers
      response = HTTParty.get("#{message.inbox.channel.wechat_api_url}/media/get",
        query: {
          access_token: access_token,
          media_id: media_id
        }
      )

      if response.success? && response.headers['content-type']&.start_with?('image/', 'audio/', 'video/')
        create_attachment(message, response, media_type, media_id)
      else
        Rails.logger.error "WeChat media download failed: #{response.parsed_response}"
      end
    rescue StandardError => e
      Rails.logger.error "WeChat media download error: #{e.message}"
    end
  end

  private

  def create_attachment(message, response, media_type, media_id)
    content_type = response.headers['content-type']
    file_extension = determine_file_extension(content_type, media_type)
    filename = "wechat_#{media_type}_#{media_id}#{file_extension}"

    # Create temporary file
    temp_file = Tempfile.new([filename, file_extension])
    temp_file.binmode
    temp_file.write(response.body)
    temp_file.rewind

    message.attachments.create!(
      account_id: message.account_id,
      file_type: map_media_type_to_file_type(media_type),
      file: {
        io: temp_file,
        filename: filename,
        content_type: content_type
      }
    )
  ensure
    temp_file&.close
    temp_file&.unlink
  end

  def determine_file_extension(content_type, media_type)
    case content_type
    when /image\/jpeg/
      '.jpg'
    when /image\/png/
      '.png'
    when /image\/gif/
      '.gif'
    when /audio\/mpeg/
      '.mp3'
    when /audio\/amr/
      '.amr'
    when /video\/mp4/
      '.mp4'
    else
      case media_type
      when 'image'
        '.jpg'
      when 'voice'
        '.amr'
      when 'video'
        '.mp4'
      else
        '.bin'
      end
    end
  end

  def map_media_type_to_file_type(media_type)
    case media_type
    when 'image'
      'image'
    when 'voice'
      'audio'
    when 'video', 'shortvideo'
      'video'
    else
      'file'
    end
  end
end
