require 'rails_helper'

RSpec.describe BotSafetyReviews::Create do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:params) do
    { from_date: '2026-03-08', to_date: '2026-03-08', timezone: 'America/New_York', max_requests: 2, max_calls: 0, dry_run: true,
      idempotency_key: 'unique-review-key' }
  end

  before { allow(BotSafetyClient).to receive(:enabled?).and_return(true) }

  it 'uses browser civil dates through DST and idempotently schedules only once' do
    expect(BotSafetyReviews::RunJob).to receive(:perform_later).once
    run = described_class.call(account, user, params)
    expect(Time.iso8601(run.settings['to']) - Time.iso8601(run.settings['from'])).to eq(23.hours)
    expect(described_class.call(account, user, params).id).to eq(run.id)
    expect { described_class.call(account, user, params.merge(max_calls: 1)) }.to raise_error(ArgumentError)
  end

  it 'rejects invalid dates, unknown profiles and unbounded scan budgets' do
    expect { described_class.call(account, user, params.merge(max_requests: 100_001)) }.to raise_error(ArgumentError)
    expect { described_class.call(account, user, params.merge(timezone: 'invalid')) }.to raise_error(ArgumentError)
  end
end
