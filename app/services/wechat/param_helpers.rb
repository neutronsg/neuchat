module Wechat::ParamHelpers
  # WeChat Customer Service message types from JSON/XML webhook
  def wechat_message_content
    msg_type = params[:MsgType] || params[:msgtype] || params['MsgType'] || params['msgtype']

    case msg_type
    when 'text'
      params[:Content] || params[:content] || params['Content'] || params['content']
    when 'image'
      '[图片]' # [Image] in Chinese
    when 'voice'
      '[语音]' # [Voice] in Chinese
    when 'video', 'shortvideo'
      '[视频]' # [Video] in Chinese
    when 'location'
      label = params[:Label] || params[:label] || params['Label'] || params['label']
      "位置: #{label}" # Location: in Chinese
    when 'link'
      title = params[:Title] || params[:title] || params['Title'] || params['title']
      url = params[:Url] || params[:url] || params['Url'] || params['url']
      "链接: #{title} - #{url}" # Link: in Chinese
    when 'miniprogrampage'
      title = params[:Title] || params[:title] || params['Title'] || params['title']
      "[小程序] #{title}" # [Mini Program] in Chinese
    else
      '[不支持的消息类型]' # [Unsupported message type] in Chinese
    end
  end

  def wechat_content_attributes
    msg_type = params[:MsgType] || params[:msgtype] || params['MsgType'] || params['msgtype']

    case msg_type
    when 'text'
      {}
    when 'image'
      {
        media_url: get_param_value(:PicUrl, :pic_url),
        media_id: get_param_value(:MediaId, :media_id)
      }
    when 'voice'
      {
        media_id: get_param_value(:MediaId, :media_id),
        format: get_param_value(:Format, :format),
        recognition: get_param_value(:Recognition, :recognition) # Voice recognition result if available
      }
    when 'video', 'shortvideo'
      {
        media_id: get_param_value(:MediaId, :media_id),
        thumb_media_id: get_param_value(:ThumbMediaId, :thumb_media_id),
        media_url: get_param_value(:MediaUrl, :media_url)
      }
    when 'location'
      {
        location_x: get_param_value(:Location_X, :location_x),
        location_y: get_param_value(:Location_Y, :location_y),
        scale: get_param_value(:Scale, :scale),
        label: get_param_value(:Label, :label)
      }
    when 'link'
      {
        title: get_param_value(:Title, :title),
        description: get_param_value(:Description, :description),
        url: get_param_value(:Url, :url)
      }
    when 'miniprogrampage'
      {
        title: get_param_value(:Title, :title),
        appid: get_param_value(:AppId, :appid),
        pagepath: get_param_value(:PagePath, :pagepath),
        thumb_media_id: get_param_value(:ThumbMediaId, :thumb_media_id)
      }
    else
      {}
    end
  end

  def wechat_from_user
    get_param_value(:FromUserName, :from_user_name, :FromUser, :from_user)
  end

  def wechat_to_user
    get_param_value(:ToUserName, :to_user_name, :ToUser, :to_user)
  end

  private

  def get_param_value(*keys)
    keys.each do |key|
      # Try both symbol and string versions, and camelCase/snake_case
      [key, key.to_s, key.to_s.camelize(:lower), key.to_s.underscore].each do |variant|
        value = params[variant]
        return value if value.present?
      end
    end
    nil
  end

  def wechat_message_id
    get_param_value(:MsgId, :msg_id)
  end

  def wechat_create_time
    timestamp = get_param_value(:CreateTime, :create_time)
    Time.at(timestamp.to_i) if timestamp
  end

  def wechat_msg_type
    get_param_value(:MsgType, :msgtype)
  end

  def wechat_event_type
    get_param_value(:Event, :event)
  end

  def wechat_event_key
    get_param_value(:EventKey, :event_key)
  end

  # Media file handling
  def has_media_file?
    %w[image voice video shortvideo].include?(wechat_msg_type)
  end

  def media_file_url
    case wechat_msg_type
    when 'image'
      get_param_value(:PicUrl, :pic_url)
    when 'voice', 'video', 'shortvideo'
      # Need to download from WeChat servers using MediaId
      nil # Will be handled by download service
    else
      nil
    end
  end

  def media_id
    get_param_value(:MediaId, :media_id)
  end

  # Location handling
  def has_location?
    wechat_msg_type == 'location'
  end

  def location_data
    return nil unless has_location?

    {
      latitude: get_param_value(:Location_X, :location_x).to_f,
      longitude: get_param_value(:Location_Y, :location_y).to_f,
      scale: get_param_value(:Scale, :scale).to_i,
      label: get_param_value(:Label, :label)
    }
  end

  # Contact info
  def contact_name
    # WeChat doesn't provide real name in webhook, use OpenID as identifier
    "WeChat User"
  end

  def contact_identifier
    wechat_from_user
  end
end
