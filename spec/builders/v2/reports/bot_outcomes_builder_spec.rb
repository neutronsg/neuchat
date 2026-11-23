require 'rails_helper'
RSpec.describe V2::Reports::BotOutcomesBuilder do
  let(:account) { create(:account) }
  let(:params) { { from: 1.day.ago.to_i, to: 1.day.from_now.to_i } }

  def state(account: self.account, **attrs)
    BotConversationOutcome.create!({ account: account, conversation: create(:conversation, account: account),
                                     categories: ['CMS portal'] }.merge(attrs))
  end

  it 'uses the same cohort for rates, deduplicates categories, and preserves independent outcomes' do
    state(escalated_at: Time.current, closed_at: Time.current, all_solved: true,
          escalations: [{ 'reason'=>'requires_other_person', 'destination'=>'oca_support' }])
    state(categories: ['CMS portal', 'Sign-up/login'])
    state(account: create(:account), all_solved: true, closed_at: Time.current)
    data = described_class.new(account, params).build
    expect(data.values_at(:conversation_count, :resolution_rate, :escalation_rate)).to eq([2, 50.0, 50.0])
    expect(data[:categories]).to eq('CMS portal'=>2, 'Sign-up/login'=>1)
    expect(data[:detail_total]).to eq(1)
  end

  it 'does not count solved but open, closed but unresolved, or out-of-period records as resolutions' do
    state(all_solved: true)
    state(closed_at: Time.current)
    state(created_at: 3.days.ago, all_solved: true, closed_at: Time.current)
    expect(described_class.new(account, params).build[:resolution_rate]).to eq(0)
  end

  it 'exports one row per conversation and rejects excessive or malformed ranges' do
    state
    expect(CSV.parse(described_class.new(account, params).csv).size).to eq(2)
    expect { described_class.new(account, from: 'oops', to: Time.current.to_i) }.to raise_error(ArgumentError)
    expect { described_class.new(account, from: Time.current.to_i, to: 100.days.ago.to_i) }.to raise_error(ArgumentError)
  end

  it 'includes the final fractional second of a Singapore day but excludes the next midnight' do
    start = Time.iso8601('2026-11-18T16:00:00Z')
    finish = Time.iso8601('2026-11-19T16:00:00Z')
    state(created_at: start - 0.001)
    state(created_at: start)
    state(created_at: finish - 0.001)
    state(created_at: finish)
    data = described_class.new(account, from: start.to_i, to: finish.to_i).build
    expect(data[:conversation_count]).to eq(2)
    expect(data[:days].pluck(:day)).to eq(['2026-11-19'])
    expect(described_class.new(account, from: start.to_i, to: (start + 365.days).to_i).build[:days].size).to eq(365)
  end

  it 'rejects excessive daily output before allocating it' do
    expect { described_class.new(account, from: 0, to: 50_001.days.to_i).build }.to raise_error(BotReportLimitError)
  end

  it 'groups by named browser timezone and preserves the complete DST day' do
    start = Time.iso8601('2026-03-08T05:00:00Z')
    finish = Time.iso8601('2026-03-09T04:00:00Z')
    state(created_at: start - 0.001)
    state(created_at: start)
    state(created_at: finish - 0.001)
    state(created_at: finish)
    args = { from: start.to_i, to: finish.to_i, timezone: 'America/New_York' }
    ny = described_class.new(account, args).build
    expect(ny[:conversation_count]).to eq(2)
    expect(ny[:days].pluck(:day)).to eq(['2026-03-08'])
    expect(ny[:timezone]).to eq('America/New_York')
    sg = described_class.new(account, args.merge(timezone: 'Asia/Singapore')).build
    expect(sg[:conversation_count]).to eq(2)
    expect(sg[:days].pluck(:day)).to eq(%w[2026-03-08 2026-03-09])
    expect { described_class.new(account, args.merge(timezone: 'invalid/zone')) }.to raise_error(ArgumentError)
  end
end
