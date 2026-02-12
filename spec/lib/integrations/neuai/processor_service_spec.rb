require 'rails_helper'

RSpec.describe Integrations::Neuai::ProcessorService do
  subject(:service) { described_class.new(hook: hook, event: event) }

  let(:account) { create(:account) }
  let(:hook) do
    create(
      :integrations_hook,
      account: account,
      app_id: 'neuai',
      settings: {
        api_key: 'app-test-key',
        neuai_url: 'https://dify.example.com/v1',
        agent_id: 'workflow-id-123'
      }
    )
  end

  describe '#perform' do
    context 'when event is rephrase' do
      let(:event) do
        {
          'name' => 'rephrase',
          'data' => {
            'content' => 'This is a test message'
          }
        }
      end
      let(:dify_response) do
        {
          'data' => {
            'status' => 'succeeded',
            'outputs' => {
              'text' => 'This is a rephrased message'
            }
          }
        }.to_json
      end

      it 'calls Dify workflow API and returns output text' do
        stub_request(:post, 'https://dify.example.com/v1/workflows/run')
          .with do |request|
            body = JSON.parse(request.body)
            body['inputs']['query'] == 'This is a test message' &&
              body['inputs']['action'] == 'rephrase' &&
              body['response_mode'] == 'blocking' &&
              body['user'].present? &&
              request.headers['Authorization'] == 'Bearer app-test-key'
          end
          .to_return(status: 200, body: dify_response, headers: {})

        result = service.perform
        expect(result).to eq({ message: 'This is a rephrased message' })
      end
    end

    context 'when event is summarize' do
      let!(:conversation) { create(:conversation, account: account) }
      let(:event) do
        {
          'name' => 'summarize',
          'data' => {
            'conversation_display_id' => conversation.display_id
          }
        }
      end
      let(:dify_response) do
        {
          'data' => {
            'status' => 'succeeded',
            'outputs' => {
              'answer' => 'Summary content'
            }
          }
        }.to_json
      end

      before do
        create(:message, account: account, conversation: conversation, message_type: :incoming, content: 'hello agent')
        create(:message, account: account, conversation: conversation, message_type: :outgoing, content: 'hello customer')
      end

      it 'sends action with conversation summary prompt and returns answer output' do
        stub_request(:post, 'https://dify.example.com/v1/workflows/run')
          .with do |request|
            body = JSON.parse(request.body)
            body['inputs']['action'] == 'summarize' &&
              body['inputs']['query'].include?('hello agent') &&
              body['inputs']['query'].include?('hello customer')
          end
          .to_return(status: 200, body: dify_response, headers: {})

        result = service.perform
        expect(result).to eq({ message: 'Summary content' })
      end
    end

    context 'when Dify workflow execution fails' do
      let(:event) do
        {
          'name' => 'rephrase',
          'data' => {
            'content' => 'This is a test message'
          }
        }
      end
      let(:dify_failed_response) do
        {
          'data' => {
            'status' => 'failed',
            'error' => 'workflow failed'
          }
        }.to_json
      end

      it 'returns a structured error payload' do
        stub_request(:post, 'https://dify.example.com/v1/workflows/run')
          .to_return(status: 200, body: dify_failed_response, headers: {})

        result = service.perform

        expect(result).to eq(
          {
            error: {
              error: {
                message: 'workflow failed'
              }
            },
            error_code: 422
          }
        )
      end
    end
  end
end
