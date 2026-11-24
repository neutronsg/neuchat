require 'rails_helper'

RSpec.describe BotSafetyReviews::ReviewItem do
  it 'does not let a worker with an expired ownership token overwrite a recovered result' do
    account = create(:account)
    run = BotSafetyReviewRun.create!(account: account, idempotency_key: 'fenced-worker', cutoff_at: Time.current, high_water_id: 1,
                                     summary: { lease_owner: 'new-worker' })
    item = run.items.create!(message_id: 1, conversation_id: 1, status: 'running')
    expect { described_class.new(run, item, 'old-worker').call }.to raise_error(BotSafetyReviewRun::LeaseLost)
    expect(item.reload.status).to eq('running')
  end

  it 'selects partially missing checks for issues instead of hiding them outside the filter' do
    run = instance_double(BotSafetyReviewRun, settings: { 'scope' => 'issues' })
    evidence = { audit: { 'events' => [{ 'enforced' => true, 'status' => 'allow' }] } }
    allow(BotSafetyReviews::Evidence).to receive(:complete?).with(evidence).and_return(false)
    expect(described_class.new(run, nil, 'worker').send(:selected?, evidence)).to be(true)
  end
end
