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

  before do
    allow(Kbase::NeuaiClient).to receive(:new).and_return(neuai_client)
  end

  describe 'GET /api/v1/accounts/:account_id/knowledge_bases/:knowledge_base_id/documents' do
    it 'returns enabled as false when NeuAI document is disabled' do
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

    it 'falls back to local documents when NeuAI list fails' do
      allow(neuai_client).to receive(:list_documents).with('dataset_123')
        .and_raise(Kbase::NeuaiClient::Error, 'Connection reset by peer - SSL_connect')

      get "/api/v1/accounts/#{account.id}/knowledge_bases/#{knowledge_base.id}/documents",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:documents].length).to eq(1)
      expect(body[:documents].first[:id]).to eq(document.id)
      expect(body[:documents].first[:indexing_status]).to eq('unknown')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/knowledge_bases/:knowledge_base_id/documents' do
    let(:uploaded_file) do
      tempfile = Tempfile.new(['knowledge-base', '.txt'])
      tempfile.write("hello\nworld")
      tempfile.rewind
      Rack::Test::UploadedFile.new(tempfile.path, 'text/plain', original_filename: 'guide.txt')
    end

    it 'creates a document with custom chunk settings' do
      expected_process_rule = {
        mode: 'custom',
        rules: {
          pre_processing_rules: [
            { id: 'remove_extra_spaces', enabled: true },
            { id: 'remove_urls_emails', enabled: false }
          ],
          segmentation: {
            separator: "\n\n",
            max_tokens: 1200,
            chunk_overlap: 100
          }
        }
      }

      allow(neuai_client).to receive(:create_document_by_file).with(
        'dataset_123',
        an_instance_of(ActionDispatch::Http::UploadedFile),
        name: 'Guide',
        process_rule: expected_process_rule
      ).and_return(
        {
          'document' => {
            'id' => 'doc_new',
            'indexing_status' => 'waiting',
            'enabled' => true,
            'word_count' => 18
          }
        }
      )

      post "/api/v1/accounts/#{account.id}/knowledge_bases/#{knowledge_base.id}/documents",
           params: {
             file: uploaded_file,
             name: 'Guide',
             chunk_settings: {
               separator: '\n\n',
               max_tokens: 1200,
               chunk_overlap: 100,
               pre_processing_rules: {
                 remove_extra_spaces: true,
                 remove_urls_emails: false
               }
             }.to_json
           },
           headers: admin.create_new_auth_token

      expect(response).to have_http_status(:created)
      expect(knowledge_base.documents.find_by(neuai_document_id: 'doc_new')).to be_present
    end
  end

  describe 'GET /api/v1/accounts/:account_id/knowledge_bases/:knowledge_base_id/documents/:id/chunk_settings' do
    it 'returns normalized chunk settings from the document process rule' do
      allow(neuai_client).to receive(:get_document).with('dataset_123', 'doc_123').and_return(
        {
          'document_process_rule' => {
            'mode' => 'custom',
            'rules' => {
              'pre_processing_rules' => [
                { 'id' => 'remove_extra_spaces', 'enabled' => true },
                { 'id' => 'remove_urls_emails', 'enabled' => false }
              ],
              'segmentation' => {
                'separator' => "\n\n",
                'max_tokens' => 1024,
                'chunk_overlap' => 50
              }
            }
          },
          'dataset_process_rule' => nil
        }
      )

      get "/api/v1/accounts/#{account.id}/knowledge_bases/#{knowledge_base.id}/documents/#{document.id}/chunk_settings",
          headers: admin.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body.dig(:chunk_settings, :editable)).to be(true)
      expect(body.dig(:chunk_settings, :max_tokens)).to eq(1024)
      expect(body.dig(:chunk_settings, :pre_processing_rules, :remove_extra_spaces)).to be(true)
      expect(body.dig(:chunk_settings, :pre_processing_rules, :remove_urls_emails)).to be(false)
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/knowledge_bases/:knowledge_base_id/documents/:id/chunk_settings' do
    it 'updates chunk settings and triggers re-indexing' do
      allow(neuai_client).to receive(:get_document).with('dataset_123', 'doc_123').and_return(
        {
          'indexing_status' => 'completed',
          'name' => 'FAQ'
        }
      )
      allow(neuai_client).to receive(:update_document_by_file).with(
        'dataset_123',
        'doc_123',
        nil,
        name: 'FAQ',
        process_rule: {
          mode: 'custom',
          rules: {
            pre_processing_rules: [
              { id: 'remove_extra_spaces', enabled: false },
              { id: 'remove_urls_emails', enabled: true }
            ],
            segmentation: {
              separator: "\n\t",
              max_tokens: 900,
              chunk_overlap: 64
            }
          }
        }
      ).and_return(
        {
          'document' => {
            'indexing_status' => 'waiting'
          }
        }
      )

      patch "/api/v1/accounts/#{account.id}/knowledge_bases/#{knowledge_base.id}/documents/#{document.id}/chunk_settings",
            params: {
              chunk_settings: {
                separator: '\n\t',
                max_tokens: 900,
                chunk_overlap: 64,
                pre_processing_rules: {
                  remove_extra_spaces: false,
                  remove_urls_emails: true
                }
              }
            },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:success]).to be(true)
      expect(body[:indexing_status]).to eq('waiting')
    end

    it 'rejects updates while the document is being processed' do
      allow(neuai_client).to receive(:get_document).with('dataset_123', 'doc_123').and_return(
        {
          'indexing_status' => 'splitting',
          'name' => 'FAQ'
        }
      )

      patch "/api/v1/accounts/#{account.id}/knowledge_bases/#{knowledge_base.id}/documents/#{document.id}/chunk_settings",
            params: {
              chunk_settings: {
                separator: '\n\n',
                max_tokens: 1024,
                chunk_overlap: 50,
                pre_processing_rules: {
                  remove_extra_spaces: false,
                  remove_urls_emails: false
                }
              }
            },
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:error]).to eq('Document is being processed, please try again later')
    end
  end
end
