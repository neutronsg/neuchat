FactoryBot.define do
  factory :channel_wechat, class: 'Channel::Wechat' do
    app_id { "wx#{SecureRandom.hex(8)}" }
    app_secret { SecureRandom.hex(16) }
    token { SecureRandom.hex(16) }
    account

    before(:create) do |channel_wechat|
      channel_wechat.define_singleton_method(:ensure_valid_app_credentials) { nil }
      channel_wechat.define_singleton_method(:setup_wechat_webhook) { nil }
    end

    after(:create) do |channel_wechat|
      create(:inbox, channel: channel_wechat, account: channel_wechat.account)
    end
  end
end
