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

  it 'rejects reversed dates for every OCA report endpoint without contacting the model service' do
    headers = admin.create_new_auth_token
    expect(BotUsageReportClient).not_to receive(:fetch)
    %w[bot_outcomes bot_outcomes_csv bot_usage bot_metrics bot_workbook].each do |endpoint|
      oversized = { from: 100, to: 0, since: 100, until: 0 }
      get "/api/v2/accounts/#{account.id}/reports/#{endpoint}", params: oversized, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('invalid_range')
    end
  end

  it 'protects workbook downloads and returns a real Excel attachment for an administrator' do
    endpoint = "/api/v2/accounts/#{account.id}/reports/bot_workbook"
    expect(BotUsageReportClient).not_to receive(:fetch)
    get endpoint, params: params
    expect(response).to have_http_status(:unauthorized)
    get endpoint, params: params, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    other = create(:account)
    get "/api/v2/accounts/#{other.id}/reports/bot_workbook", params: params, headers: admin.create_new_auth_token
    expect(response).not_to have_http_status(:ok)
    allow(ENV).to receive(:[]).with('OCA_BOT_REPORTS_ENABLED').and_return('false')
    get endpoint, params: params, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'serves a dated workbook even when metering is unavailable' do
    allow(BotUsageReportClient).to receive(:fetch).and_raise(IOError)
    get "/api/v2/accounts/#{account.id}/reports/bot_workbook", params: params, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')
    expect(response.headers['Content-Disposition']).to include('bot-report-', '.xlsx')
    expect(response.body[0, 2]).to eq('PK')
  end

  it 'accepts annual ranges across all endpoints and reports excessive data explicitly' do
    allow(BotUsageReportClient).to receive(:fetch).and_return({})
    headers = admin.create_new_auth_token
    annual = { from: 1.year.ago.to_i, to: Time.current.to_i, since: 1.year.ago.to_i, until: Time.current.to_i }
    %w[bot_outcomes bot_outcomes_csv bot_usage bot_metrics bot_workbook].each do |endpoint|
      get "/api/v2/accounts/#{account.id}/reports/#{endpoint}", params: annual, headers: headers
      expect(response).to have_http_status(:ok)
    end
    allow(BotUsageReportClient).to receive(:fetch).and_raise(BotReportLimitError)
    %w[bot_usage bot_workbook].each do |endpoint|
      get "/api/v2/accounts/#{account.id}/reports/#{endpoint}", params: annual, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('report_too_large')
    end
  end

  it 'rejects excessive untracked history in both metrics and workbook without fetching usage' do
    stub_const('V2::Reports::BotMetricsBuilder::OCA_CONVERSATION_LIMIT', 2)
    inbox = create(:inbox, account: account)
    create(:agent_bot_inbox, inbox: inbox)
    3.times { create(:conversation, account: account, inbox: inbox, created_at: 1.hour.ago) }
    expect(account.bot_conversation_outcomes.count).to eq(0)
    expect(BotUsageReportClient).not_to receive(:fetch)
    filters = params.merge(since: params[:from], until: params[:to], conversation_limit: 999_999)
    %w[bot_metrics bot_workbook].each do |endpoint|
      get "/api/v2/accounts/#{account.id}/reports/#{endpoint}", params: filters, headers: admin.create_new_auth_token
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('report_too_large')
    end
  end
end
