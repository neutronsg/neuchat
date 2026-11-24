require 'rails_helper'

RSpec.describe 'Safety review access', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/bot_safety_reviews" }
  let!(:run) do
    BotSafetyReviewRun.create!(account: account, user: admin, idempotency_key: 'controller-test', cutoff_at: Time.current, high_water_id: 0,
                               status: 'completed')
  end

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('OCA_BOT_REPORTS_ENABLED').and_return('true')
    allow(BotSafetyClient).to receive(:enabled?).with(account.id).and_return(true)
  end

  it 'denies non-admins and cross-account access to raw exports and results' do
    get path, headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    post "#{path}/import_results", headers: agent.create_new_auth_token
    expect(response).to have_http_status(:unauthorized)
    post "#{path}/import_results", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
    other = BotSafetyReviewRun.create!(account: create(:account), idempotency_key: 'other-account', cutoff_at: Time.current, high_water_id: 0)
    get "#{path}/#{other.id}", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
    get "#{path}/#{other.id}/download", headers: admin.create_new_auth_token
    expect(response).to have_http_status(:not_found)
  end

  it 'appends human assessments without overwriting the AI verdict' do
    item = run.items.create!(message_id: 1, conversation_id: 1, status: 'completed', result: { result: { verdict: 'possible_false_positive' } })
    2.times do |i|
      post "#{path}/#{run.id}/annotate", params: { item_id: item.id, verdict: 'observing', review_note: "Review #{i}" },
                                         headers: admin.create_new_auth_token
      expect(response).to have_http_status(:created)
    end
    expect(item.notes.count).to eq(2)
    expect(item.reload.result.dig('result', 'verdict')).to eq('possible_false_positive')
    post "#{path}/#{run.id}/annotate", params: { item_id: item.id, verdict: 'invalid', review_note: 'Bad' }, headers: admin.create_new_auth_token
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
