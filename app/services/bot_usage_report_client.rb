require 'net/http'
class BotUsageReportClient
  def self.fetch(account_id, params)
    raise ArgumentError, 'Reporting account unavailable' unless account_id.to_s == ENV.fetch('OCA_BOT_ACCOUNT_ID', '')

    uri = endpoint(account_id, params)
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{ENV.fetch('OCA_BOT_USAGE_TOKEN')}"
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 3, read_timeout: 35) do |http|
      http.request(request)
    end
    raise BotReportLimitError if response.code == '413'

    raise IOError, 'Usage unavailable' unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def self.endpoint(account_id, params)
    base = URI(ENV.fetch('OCA_BOT_USAGE_URL'))
    raise ArgumentError, 'Invalid usage endpoint' unless %w[http https].include?(base.scheme) && !base.userinfo && !base.query

    from, to = period(params)
    base.query = URI.encode_www_form(account: account_id, from: from.iso8601, to: to.iso8601, timezone: timezone(params))
    base
  end

  def self.timezone(params)
    name = params[:timezone].presence || 'Asia/Singapore'
    TZInfo::Timezone.get(name).identifier
  rescue TZInfo::InvalidTimezoneIdentifier
    raise ArgumentError, 'Invalid timezone'
  end

  def self.period(params)
    timezone(params)
    from = Time.at(Integer(params[:from])).utc
    to = Time.at(Integer(params[:to])).utc
    raise ArgumentError, 'Invalid range' unless to > from

    [from, to]
  end
end
