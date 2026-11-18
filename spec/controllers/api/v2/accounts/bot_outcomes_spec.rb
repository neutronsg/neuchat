require 'rails_helper'
RSpec.describe 'OCA bot report access', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:params) { { from: 1.day.ago.to_i, to: Time.current.to_i } }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('OCA_BOT_REPORTS_ENABLED').and_return('true')
    allow(ENV).to receive(:[]).with('OCA_BOT_ACCOUNT_ID').and_return(account.id.to_s)
  end

  it 'requires an authenticated report administrator' do
    get "/api/v2/accounts/#{account.id}/reports/bot_outcomes", params: params
    expect(response).to have_http_status(:unauthorized)
    get "/api/v2/accounts/#{account.id}/reports/bot_outcomes", params: params, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    get "/api/v2/accounts/#{account.id}/reports/bot_outcomes", params: params, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['conversation_count']).to eq(0)
  end

  it 'does not expose reports to another account or when disabled' do
    other = create(:account)
    get "/api/v2/accounts/#{other.id}/reports/bot_outcomes", params: params, headers: admin.create_new_auth_token
    expect(response).not_to have_http_status(:ok)
    allow(ENV).to receive(:[]).with('OCA_BOT_REPORTS_ENABLED').and_return('false')
    get "/api/v2/accounts/#{account.id}/reports/bot_outcomes", params: params, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'rejects more than 93 days for every OCA report endpoint without contacting the model service' do
    headers = admin.create_new_auth_token
    expect(BotUsageReportClient).not_to receive(:fetch)
    %w[bot_outcomes bot_outcomes_csv bot_usage bot_metrics].each do |endpoint|
      oversized = { from: 0, to: 94.days.to_i, since: 0, until: 94.days.to_i }
      get "/api/v2/accounts/#{account.id}/reports/#{endpoint}", params: oversized, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('invalid_range')
    end
  end
end
