require 'rails_helper'
require 'digest'

RSpec.describe BotSafetyReviews do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, display_id: 900_000) }
  let(:message) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'My OTP is not arriving')
  end
  let(:run) do
    BotSafetyReviewRun.create!(account: account, idempotency_key: 'integrated-local', cutoff_at: Time.current,
                               high_water_id: account.messages.maximum(:id),
                               settings: { from: 1.day.ago.iso8601, to: 1.day.from_now.iso8601, max_requests: 5, max_calls: 1,
                                           profile: { name: 'mock', version: 'mock-v1', maxInputBytes: 100_000 } })
  end
  let(:records) do
    [
      { kind: 'received', payload: {} },
      { kind: 'context', payload: { references: [{ id: message.id, hash: Digest::SHA256.hexdigest(message.content) }] } },
      { kind: 'plan', payload: { expectedChecks: ['custom.input', 'custom.output'] } },
      { kind: 'finished', payload: {} }
    ].each_with_index.map do |r, i|
      r.merge(sequence: i, request_id: 'request', attempt_id: 'attempt', created_at: Time.current.iso8601).deep_stringify_keys
    end
  end
  let(:events) do
    %w[input output].map do |stage|
      { 'attempt_id' => 'attempt', 'provider' => 'custom', 'stage' => stage, 'enforced' => true, 'status' => 'allow',
        'created_at' => Time.current.iso8601 }
    end
  end

  before do
    create(:agent_bot_inbox, account: account, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                     content: 'Please check your registered mobile number', content_attributes: { bot_trigger_message_id: message.id })
    audit = { 'records' => records, 'events' => events, 'missingBlobs' => [], 'blobs' => {} }
    args = { conversation: conversation.display_id, message: message.id }
    allow(BotSafetyReviews::Client).to receive(:call).with(account.id, '/internal/safety/evidence', args, post: false).and_return(audit)
  end

  it 'reviews once and exports the same canonical evidence with mocked model calls' do
    result = { 'result' => { 'verdict' => 'no_issue', 'reason' => 'Mock reviewer result', 'messageIds' => [message.id] } }
    expect(BotSafetyReviews::Client).to receive(:call).with(account.id, '/internal/safety/review', anything, post: true).once.and_return(result)
    BotSafetyReviews::RunJob.perform_now(run.id)
    expect(run.reload).to have_attributes(status: 'completed', calls_reserved: 1)
    BotSafetyReviews::RunJob.perform_now(run.id)
    BotSafetyReviews::ExportJob.perform_now(run.id)
    expect(run.reload.export_status).to eq('ready')
    Zip::File.open_buffer(run.export_file.download) do |zip|
      data = JSON.parse(zip.read('records.jsonl').lines.first)
      expect(data.dig('evidence', 'transcript').pluck('content')).to include(message.content)
      expect(data.dig('evidence', 'audit', 'records').length).to eq(4)
      expect(data.dig('result', 'result', 'verdict')).to eq('no_issue')
    end
  end
end
