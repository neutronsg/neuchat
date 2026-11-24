require 'rails_helper'

RSpec.describe BotSafetyReviews::RunJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let!(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming) }
  let!(:run) do
    BotSafetyReviewRun.create!(account: account, idempotency_key: 'job-test-key', cutoff_at: Time.current, high_water_id: message.id,
                               settings: { from: 1.day.ago.iso8601, to: 1.day.from_now.iso8601, max_requests: 10, max_calls: 1,
                                           profile: { name: 'mock', version: 'v1', maxInputBytes: 100_000 } })
  end
  let(:evidence) { { transcript: [{ id: message.id }], audit: { 'events' => [] }, manifest: { messages: [{ id: message.id, hash: 'fixed' }] } } }
  let(:inbox) { create(:inbox, account: account) }

  before do
    create(:agent_bot_inbox, account: account, inbox: inbox)
    allow(BotSafetyReviews::Evidence).to receive(:call).and_return(evidence)
    allow(BotSafetyReviews::Evidence).to receive(:complete?).and_return(true)
  end

  it 'reserves once, ignores duplicate live workers and never automatically repeats an unknown API outcome' do
    run.update!(status: 'running', lease_until: 1.minute.from_now)
    expect(BotSafetyReviews::Client).not_to receive(:call)
    described_class.perform_now(run.id)
    expect(run.reload.calls_reserved).to eq(0)
    run.update!(lease_until: 1.minute.ago, calls_reserved: 1)
    run.items.create!(message_id: message.id, conversation_id: conversation.id, status: 'running')
    described_class.perform_now(run.id)
    expect(run.reload.status).to eq('incomplete')
    expect(run.items.first.result['error']).to eq('previous_call_outcome_unknown')
    described_class.perform_now(run.id)
    expect(run.reload.calls_reserved).to eq(1)
  end

  it 'exports old profile-configured batches without runtime model calls' do
    expect(BotSafetyReviews::Client).not_to receive(:call)
    described_class.perform_now(run.id)
    expect(run.reload.status).to eq('completed')
    expect(run.calls_reserved).to eq(0)
    expect(run.items.first.result['outcome']).to eq('export_only')
    described_class.perform_now(run.id)
  end

  it 'does not submit changed source evidence or evidence outside the batch cutoff' do
    run.items.create!(message_id: message.id, conversation_id: conversation.id, manifest: { changed: true })
    expect(BotSafetyReviews::Client).not_to receive(:call)
    described_class.perform_now(run.id)
    expect(run.items.first.reload.status).to eq('insufficient_evidence')
    expect(run.calls_reserved).to eq(0)
  end
end
