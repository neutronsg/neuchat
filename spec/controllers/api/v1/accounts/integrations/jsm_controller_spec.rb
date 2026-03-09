require 'rails_helper'

RSpec.describe 'JSM Integration API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, account: account) }

  before do
    create(:integrations_hook, :jsm, account: account)
  end

  describe 'POST /api/v1/accounts/:account_id/integrations/jsm/link_ticket' do
    let(:params) do
      {
        conversation_id: conversation.display_id,
        ticket_id: '10001',
        ticket_key: 'SUP-123',
        ticket_url: 'https://example.atlassian.net/browse/SUP-123'
      }
    end

    it 'links a JSM ticket to a conversation' do
      post "/api/v1/accounts/#{account.id}/integrations/jsm/link_ticket",
           params: params,
           headers: { api_access_token: admin.access_token.token },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.additional_attributes['jsm']).to eq(
        'ticket_id' => '10001',
        'ticket_key' => 'SUP-123',
        'ticket_url' => 'https://example.atlassian.net/browse/SUP-123'
      )
    end

    it 'returns validation error when no ticket identifier is provided' do
      post "/api/v1/accounts/#{account.id}/integrations/jsm/link_ticket",
           params: params.except(:ticket_id, :ticket_key),
           headers: { api_access_token: admin.access_token.token },
           as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('ticket_id or ticket_key is required')
    end

    it 'links a JSM ticket without ticket_url' do
      post "/api/v1/accounts/#{account.id}/integrations/jsm/link_ticket",
           params: params.except(:ticket_url),
           headers: { api_access_token: admin.access_token.token },
           as: :json

      expect(response).to have_http_status(:ok)
      expect(conversation.reload.additional_attributes['jsm']).to eq(
        'ticket_id' => '10001',
        'ticket_key' => 'SUP-123'
      )
    end

    it 'returns not found when JSM is not configured' do
      account.hooks.find_by(app_id: 'jsm')&.destroy!

      post "/api/v1/accounts/#{account.id}/integrations/jsm/link_ticket",
           params: params,
           headers: { api_access_token: admin.access_token.token },
           as: :json

      expect(response).to have_http_status(:not_found)
    end

    it 'rejects requests without api_access_token' do
      post "/api/v1/accounts/#{account.id}/integrations/jsm/link_ticket",
           params: params,
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('api_access_token is required')
    end

    it 'rejects non-admin access tokens' do
      post "/api/v1/accounts/#{account.id}/integrations/jsm/link_ticket",
           params: params,
           headers: { api_access_token: agent.access_token.token },
           as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body['error']).to eq('You are not authorized to do this action')
    end
  end
end
