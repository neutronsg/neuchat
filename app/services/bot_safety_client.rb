require 'net/http'

class BotSafetyClient
  def self.enabled?(account_id)
    account_id.present? && account_id.to_s == ENV.fetch('OCA_BOT_ACCOUNT_ID', '')
  end

  def self.fetch(account_id, path, params = {})
    raise ArgumentError, 'Safety account unavailable' unless enabled?(account_id)
    raise ArgumentError, 'Invalid safety operation' unless %w[/internal/safety/capabilities /internal/reports/safety].include?(path)

    uri = endpoint(account_id, path, params)
    request = Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{ENV.fetch('OCA_BOT_USAGE_TOKEN')}"
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 3, read_timeout: 10) do |http|
      http.request(request)
    end
    raise BotReportLimitError if response.code == '413'
    raise IOError, 'Safety service unavailable' unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end

  def self.endpoint(account_id, path, params)
    uri = URI(ENV.fetch('OCA_BOT_USAGE_URL'))
    raise ArgumentError, 'Invalid safety endpoint' unless %w[http https].include?(uri.scheme) && !uri.userinfo && !uri.query

    uri.path = path
    uri.query = URI.encode_www_form(params.merge(account: account_id))
    uri
  end
end
