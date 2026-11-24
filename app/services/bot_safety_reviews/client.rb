require 'net/http'

class BotSafetyReviews::Client
  PATHS = %w[/internal/safety/evidence /internal/safety/review_profiles /internal/safety/review].freeze

  def self.call(account_id, path, params = {}, post: false)
    raise ArgumentError, 'Invalid review operation' unless PATHS.include?(path) && BotSafetyClient.enabled?(account_id)

    uri = BotSafetyClient.endpoint(account_id, path, post ? {} : params)
    request = post ? Net::HTTP::Post.new(uri) : Net::HTTP::Get.new(uri)
    request['Authorization'] = "Bearer #{ENV.fetch('OCA_BOT_SAFETY_REVIEW_TOKEN')}"
    if post
      request['Content-Type'] = 'application/json'
      request.body = params.merge(account: account_id).to_json
    end
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == 'https', open_timeout: 3, read_timeout: 70) do |http|
      http.request(request)
    end
    raise IOError, 'Safety review service unavailable' unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end
end
