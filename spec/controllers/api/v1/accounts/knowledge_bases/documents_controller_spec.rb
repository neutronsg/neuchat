require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::KnowledgeBases::Documents', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:knowledge_base) do
    Kbase::KnowledgeBase.create!(
      account: account,
      name: 'Support KB',
      neuai_dataset_id: 'dataset_123'
    )
  end
  let!(:document) do
    Kbase::Document.create!(
      knowledge_base: knowledge_base,
      neuai_document_id: 'doc_123',
      name: 'FAQ',
      created_by: admin,
      updated_by: admin
    )
  end
  let(:neuai_client) { instance_double(Kbase::NeuaiClient) }

  describe 'GET /api/v1/accounts/:account_id/knowledge_bases/:knowledge_base_id/documents' do
    it 'returns enabled as false when NeuAI document is disabled' do
      allow(Kbase::NeuaiClient).to receive(:new).and_return(neuai_client)
      allow(neuai_client).to receive(:list_documents).with('dataset_123').and_return(
        {
          'data' => [
            {
              'id' => 'doc_123',
              'indexing_status' => 'completed',
              'enabled' => false,
              'word_count' => 42
            }
          ]
        }
      )

      get "/api/v1/accounts/#{account.id}/knowledge_bases/#{knowledge_base.id}/documents",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:documents].first[:enabled]).to be(false)
    end
  end
end
