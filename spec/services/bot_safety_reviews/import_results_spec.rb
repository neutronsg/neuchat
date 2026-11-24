require 'rails_helper'

RSpec.describe BotSafetyReviews::ImportResults do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:source) do
    BotSafetyReviewRun.create!(account: account, idempotency_key: 'export-source', cutoff_at: Time.current, high_water_id: 1,
                               status: 'completed', settings: { max_calls: 0 })
  end
  let!(:item) do
    source.items.create!(message_id: 1, conversation_id: 1, status: 'completed', result: { outcome: 'export_only' },
                         manifest: { messages: [{ id: 1 }] })
  end
  let(:data) do
    { format: 2, source_run_id: source.id, account_id: account.id, environment: 'sit', execution_id: 'github-123',
      reviewer: { model: 'mock', version: 'a' * 64 }, max_calls: 1, calls_attempted: 1,
      records: [{ message_id: 1, manifest: item.manifest, status: 'completed',
                  result: { result: { verdict: 'no_issue', reason: 'No safety issue found.', messageIds: [1] } } }] }
  end

  def signed(value)
    payload = value.to_json
    { payload: payload, signature: OpenSSL::HMAC.hexdigest('SHA256', 'a' * 64, payload) }.to_json
  end

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with('OCA_SAFETY_REVIEW_SIGNING_KEY', '').and_return('a' * 64)
    allow(ENV).to receive(:fetch).with('OCA_BOT_SAFETY_ENVIRONMENT', 'local').and_return('sit')
  end

  it 'imports a new immutable batch and treats repeated import as idempotent' do
    run = described_class.call(account, user, signed(data))
    expect(run.id).not_to eq(source.id)
    expect(run.calls_reserved).to eq(1)
    expect(run.settings['dry_run']).to be(false)
    expect(run.resumable?).to be(false)
    expect(item.reload.result).to eq('outcome' => 'export_only')
    expect(described_class.call(account, user, signed(data)).id).to eq(run.id)
    data[:records][0][:result][:result][:reason] = 'Changed later result.'
    expect { described_class.call(account, user, signed(data)) }.to raise_error(ArgumentError)
  end

  it 'rejects signature, cross-account/environment, changed evidence and unsupported references' do
    expect { described_class.call(account, user, signed(data).sub('github-123', 'github-124')) }.to raise_error(ArgumentError)
    [:format, :account_id, :environment, :calls_attempted].each do |key|
      bad = data.deep_dup
      bad[key] = key == :environment ? 'prod' : 999
      expect { described_class.call(account, user, signed(bad)) }.to raise_error(ArgumentError)
    end
    bad = data.deep_dup
    bad[:records][0][:result][:result][:messageIds] = [999]
    expect { described_class.call(account, user, signed(bad)) }.to raise_error(ArgumentError)
    item.update!(manifest: { messages: [{ id: 2 }] })
    expect { described_class.call(account, user, signed(data)) }.to raise_error(ArgumentError)
  end

  it 'preserves failed calls without permitting server-side resume' do
    data[:records][0].merge!(status: 'execution_error', result: { error: 'Result unavailable' })
    run = described_class.call(account, user, signed(data))
    expect(run.status).to eq('incomplete')
    expect(run.resumable?).to be(false)
    expect(run.calls_reserved).to eq(1)
    expect(run.settings['dry_run']).to be(false)
  end
end
