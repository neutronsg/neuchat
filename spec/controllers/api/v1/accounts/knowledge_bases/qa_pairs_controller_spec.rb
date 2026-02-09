require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::KnowledgeBases::QaPairs', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:knowledge_base) do
    Kbase::KnowledgeBase.create!(
      account: account,
      name: 'Support KB',
      neuai_dataset_id: 'dataset_123'
    )
  end
  let(:docx_fixture_path) { Rails.root.join('spec/assets/qa_import_template.docx') }
  let(:docx_file) do
    fixture_file_upload(
      docx_fixture_path,
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    )
  end
  let(:txt_file) do
    fixture_file_upload(
      Rails.root.join('spec/assets/contacts.csv'),
      'text/csv'
    )
  end

  describe 'POST /api/v1/accounts/:account_id/knowledge_bases/:knowledge_base_id/qa_pairs/import_docx' do
    it 'parses qa pairs from uploaded docx without persisting immediately' do
      import_service = instance_double(Kbase::QaDocxImportService)
      allow(Kbase::QaDocxImportService).to receive(:new).and_return(import_service)
      allow(import_service).to receive(:parse!).and_return(
        [
          { question: 'Q1', answer: 'A1' },
          { question: 'Q2', answer: 'A2' }
        ]
      )

      expect do
        post "/api/v1/accounts/#{account.id}/knowledge_bases/#{knowledge_base.id}/qa_pairs/import_docx",
             params: { file: docx_file },
             headers: admin.create_new_auth_token
      end.not_to change(Kbase::QaPair, :count)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:imported_count]).to eq(2)
      expect(body[:qa_pairs]).to eq(
        [
          { question: 'Q1', answer: 'A1' },
          { question: 'Q2', answer: 'A2' }
        ]
      )
    end

    it 'returns bad request when no file is uploaded' do
      post "/api/v1/accounts/#{account.id}/knowledge_bases/#{knowledge_base.id}/qa_pairs/import_docx",
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:bad_request)
    end

    it 'returns unprocessable entity when file is not docx' do
      post "/api/v1/accounts/#{account.id}/knowledge_bases/#{knowledge_base.id}/qa_pairs/import_docx",
           params: { file: txt_file },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
