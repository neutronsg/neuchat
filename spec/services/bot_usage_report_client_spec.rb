require 'rails_helper'
RSpec.describe BotUsageReportClient do
  it 'forwards named timezone and exact DST boundaries to the usage service' do
    allow(ENV).to receive(:fetch).with('OCA_BOT_USAGE_URL').and_return('http://127.0.0.1:3091/internal/reports/usage')
    params = { from: Time.iso8601('2026-11-01T04:00:00Z').to_i,
               to: Time.iso8601('2026-11-02T05:00:00Z').to_i, timezone: 'America/New_York' }
    query = URI.decode_www_form(described_class.endpoint(1, params).query).to_h
    expect(query).to include('timezone' => 'America/New_York', 'from' => '2026-11-01T04:00:00Z', 'to' => '2026-11-02T05:00:00Z')
    from, to = described_class.period(params)
    expect(to - from).to eq(25.hours)
    expect { described_class.period(params.merge(timezone: 'invalid/zone')) }.to raise_error(ArgumentError)
  end
end
