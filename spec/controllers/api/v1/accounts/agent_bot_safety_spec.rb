require 'rails_helper'

RSpec.describe 'Agent Bot safety settings', type: :request do
  let!(:account) { create(:account) }
  let!(:bot) { create(:agent_bot, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:path) { "/api/v1/accounts/#{account.id}/agent_bots/#{bot.id}" }

  before do
    allow(BotSafetyClient).to receive(:fetch).with(account.id, '/internal/safety/capabilities')
                                             .and_return({ 'modes' => %w[aws aws_shadow aws_custom custom] })
  end

  it 'updates mode atomically with a versioned audit and preserves idle settings' do
    bot.update!(idle_auto_resolve_enabled: true, idle_auto_resolve_after: 30)
    patch path, params: { safety_mode: 'aws_shadow', safety_version: 0 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(bot.reload.safety_mode).to eq('aws_shadow')
    expect(bot.safety_version).to eq(1)
    expect(bot.idle_auto_resolve?).to be(true)
    expect(bot.bot_safety_changes.last).to have_attributes(mode: 'aws_shadow', version: 1, user_id: admin.id)
  end

  it 'rejects stale writes, unavailable modes and disable-all values' do
    bot.update!(safety_mode: 'aws')
    patch path, params: { safety_mode: 'custom', safety_version: 0 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:conflict)
    patch path, params: { safety_mode: 'off', safety_version: 1 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(bot.reload.safety_mode).to eq('aws')
    expect(bot.bot_safety_changes.count).to eq(1)
  end

  it 'denies agents and cross-account access before calling the service' do
    expect(BotSafetyClient).not_to receive(:fetch)
    patch path, params: { safety_mode: 'custom', safety_version: 0 }, headers: agent.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unauthorized)
    other = create(:agent_bot, account: create(:account))
    patch "/api/v1/accounts/#{account.id}/agent_bots/#{other.id}", params: { safety_mode: 'custom', safety_version: 0 },
                                                                   headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:not_found)
  end

  it 'does not change protection when readiness fails and allows unrelated edits' do
    allow(BotSafetyClient).to receive(:fetch).and_raise(IOError)
    patch path, params: { safety_mode: 'custom', safety_version: 0 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:service_unavailable)
    expect(bot.reload.safety_mode).to be_nil
    patch path, params: { name: 'renamed' }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
  end

  it 'persists dual enforcement and rejects it when AWS is unavailable' do
    allow(BotSafetyClient).to receive(:fetch).and_return({ 'modes' => %w[custom] })
    patch path, params: { safety_mode: 'aws_custom', safety_version: 0 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:unprocessable_entity)
    expect(bot.reload.safety_mode).to be_nil
    allow(BotSafetyClient).to receive(:fetch).and_return({ 'modes' => %w[aws custom aws_custom] })
    patch path, params: { safety_mode: 'aws_custom', safety_version: 0 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(bot.reload.safety_mode).to eq('aws_custom')
    expect(bot.bot_safety_changes.last.mode).to eq('aws_custom')
  end

  it 'saves hybrid shadow atomically and rejects stale toggles' do
    allow(BotSafetyClient).to receive(:fetch).and_return({ 'modes' => %w[hybrid hybrid_shadow dual custom aws] })
    patch path, params: { safety_mode: 'hybrid', safety_version: 0 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    patch path, params: { safety_mode: 'hybrid_shadow', safety_version: 1 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    expect(bot.reload).to have_attributes(safety_mode: 'hybrid_shadow', safety_version: 2)
    patch path, params: { safety_mode: 'hybrid', safety_version: 1 }, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:conflict)
    expect(bot.reload.safety_mode).to eq('hybrid_shadow')
  end
end
