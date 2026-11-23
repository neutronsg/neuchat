require 'rails_helper'
require 'zip'

RSpec.describe V2::Reports::BotWorkbookBuilder do
  let(:account) { create(:account) }
  let(:from) { Time.iso8601('2026-11-01T16:00:00Z') }
  let(:params) { { from: from.to_i, to: (from + 1.day).to_i, page: 99, reason: 'not_a_reason' } }
  let(:usage) do
    { 'currency' => 'USD', 'storage' => 'long_term_metering', 'priceSourceMode' => 'aws_catalog', 'priceSyncStale' => true,
      'days' => [{ 'group' => '2026-11-02', 'inputTokens' => 100, 'outputTokens' => nil, 'estimatedCostUsd' => 0,
                   'estimatedGuardrailCostUsd' => nil, 'unpricedGuardrailCalls' => 1 }],
      'total' => { 'inputTokens' => 100, 'estimatedCostUsd' => 0, 'estimatedGuardrailCostUsd' => nil, 'usageMissingCalls' => 1 } }
  end

  before do
    allow(BotSafetyClient).to receive(:fetch).and_return({ 'groups' => [], 'events' => [], 'comparison' => {} })
    expected = params.slice(:from, :to).merge(timezone: params[:timezone] || 'Asia/Singapore')
    allow(BotUsageReportClient).to receive(:fetch).with(account.id, expected).and_return(usage)
  end

  def workbook
    stream = described_class.new(account, params).to_stream
    files = nil
    Zip::File.open_buffer(stream) { |zip| files = zip.entries.to_h { |entry| [entry.name, Nokogiri::XML(entry.get_input_stream.read)] } }
    files
  end

  def rows(xml)
    xml.remove_namespaces!.xpath('//sheetData/row').map do |row|
      row.xpath('c').map { |cell| cell.at_xpath('is/t|v')&.text }
    end
  end

  it 'exports all ten sheets, all tracked conversations and every escalation, ignoring screen pagination/reason' do
    26.times do |index|
      conversation = create(:conversation, account: account)
      BotConversationOutcome.create!(account: account, conversation: conversation, created_at: from,
                                     categories: ['=HYPERLINK("https://example.invalid")'], escalated_at: from,
                                     escalations: Array.new(2) do |i|
                                       { 'at' => from.iso8601, 'reason' => 'requires_other_person', 'destination' => 'company_admin',
                                         'consentMessageId' => (index * 2) + i, 'message_id' => 10 }
                                     end)
    end
    other = create(:account)
    BotConversationOutcome.create!(account: other, conversation: create(:conversation, account: other), created_at: from)
    BotConversationOutcome.create!(account: account, conversation: create(:conversation, account: account), created_at: from + 1.day)
    files = workbook
    expect(files['xl/workbook.xml'].remove_namespaces!.xpath('//sheet').map { |s| s['name'] }).to eq(
      ['Summary', 'Daily metrics', 'Enquiry categories', 'Token usage', 'Cost estimates', 'Conversations', 'Escalations', 'Safety summary', 'Safety events', 'Shadow comparison']
    )
    expect(rows(files['xl/worksheets/sheet6.xml']).size).to eq(27)
    expect(rows(files['xl/worksheets/sheet7.xml']).size).to eq(53)
    expect(rows(files['xl/worksheets/sheet2.xml'])[1]).to eq(%w[2026-11-02 26 0 26])
    expect(files.values.sum { |xml| xml.remove_namespaces!.xpath('//f').size }).to eq(0)
  end

  it 'shows missing safety as unavailable, without removing other sheets' do
    allow(BotSafetyClient).to receive(:fetch).and_raise(IOError)
    files = workbook
    [8, 9, 10].each { |index| expect(rows(files["xl/worksheets/sheet#{index}.xml"])[1]).to eq(['Unavailable']) }
  end

  it 'formats safety timestamps using the same browser timezone and preserves missing tokens' do
    params[:timezone] = 'America/New_York'
    allow(BotUsageReportClient).to receive(:fetch).with(account.id, params.slice(:from, :to, :timezone)).and_return(usage)
    allow(BotSafetyClient).to receive(:fetch).and_return({ 'groups' => [], 'comparison' => {},
      'events' => [{ 'created_at' => '2026-11-01T06:30:00Z', 'input_tokens' => nil }] })
    event = rows(workbook['xl/worksheets/sheet9.xml'])[1]
    expect(event.first).to eq('2026-11-01T01:30:00-05:00')
    expect(event[14]).not_to eq('0')
  end

  it 'preserves unavailable and zero costs separately and includes pricing metadata' do
    files = workbook
    costs = rows(files['xl/worksheets/sheet5.xml'])
    expect(costs[1][1..2]).to eq(%w[0 Unavailable])
    summary = rows(files['xl/worksheets/sheet1.xml']).to_h
    expect(summary['Price sync stale']).to eq('1')
    expect(summary['Timezone']).to eq('Asia/Singapore')
    expect(rows(files['xl/worksheets/sheet4.xml'])[2]).to include('Unavailable', '100')
  end

  it 'still exports outcomes with explicit missing usage when the usage service fails' do
    allow(BotUsageReportClient).to receive(:fetch).and_raise(IOError, 'unavailable')
    files = workbook
    expect(rows(files['xl/worksheets/sheet1.xml']).to_h['Usage status']).to eq('Unavailable')
    expect(rows(files['xl/worksheets/sheet4.xml'])[1]).to all(eq('Unavailable'))
    expect(rows(files['xl/worksheets/sheet5.xml'])[1]).to all(eq('Unavailable'))
  end

  it 'uses the selected Singapore dates in the filename, with an exclusive end' do
    expect(described_class.new(account, params).filename).to eq('bot-report-2026-11-02.xlsx')
    expect(described_class.new(account, params.merge(to: (from + 93.days).to_i)).filename).to eq('bot-report-2026-11-02-to-2027-02-02.xlsx')
    expect { described_class.new(account, params.merge(to: (from + 365.days).to_i)) }.not_to raise_error
  end

  context 'with a browser timezone spanning a DST change' do
    let(:from) { Time.iso8601('2026-03-08T05:00:00Z') }
    let(:params) { { from: from.to_i, to: Time.iso8601('2026-03-09T04:00:00Z').to_i, timezone: 'America/New_York' } }

    it 'exports local dates and different start/end offsets without changing instants' do
      expect(described_class.new(account, params).filename).to eq('bot-report-2026-03-08.xlsx')
      summary = rows(workbook['xl/worksheets/sheet1.xml']).to_h
      expect(summary['Timezone']).to eq('America/New_York')
      expect(summary['Period start (inclusive)']).to eq('2026-03-08T00:00:00-05:00')
      expect(summary['Period end (exclusive)']).to eq('2026-03-09T00:00:00-04:00')
    end
  end

  [
    ['America/New_York', '2026-03-08T04:30:00Z', '2026-03-07T23:30:00-05:00'],
    ['Asia/Singapore', '2026-03-08T04:30:00Z', '2026-03-08T12:30:00+08:00'],
    ['America/New_York', '2026-03-08T07:30:00Z', '2026-03-08T03:30:00-04:00'],
    ['America/New_York', '2026-11-01T05:30:00Z', '2026-11-01T01:30:00-04:00'],
    ['America/New_York', '2026-11-01T06:30:00Z', '2026-11-01T01:30:00-05:00']
  ].each do |zone, at, expected|
    context "with event #{at} in #{zone}" do
      let(:from) { Time.iso8601(at) - 1.hour }
      let(:params) { super().merge(timezone: zone) }

      it 'converts escalation and price sync timestamps consistently across sheets' do
        usage['priceLastSyncedAt'] = at
        event = { 'at' => at, 'reason' => 'user_requested_support', 'destination' => 'oca_support' }
        BotConversationOutcome.create!(account: account, conversation: create(:conversation, account: account), created_at: from,
                                       escalated_at: Time.iso8601(at), escalations: [event])
        files = workbook
        expect(rows(files['xl/worksheets/sheet7.xml'])[1][1]).to eq(expected)
        expect(rows(files['xl/worksheets/sheet6.xml'])[1][3]).to eq(expected)
        expect(rows(files['xl/worksheets/sheet1.xml']).to_h['Prices last synced']).to eq(expected)
      end
    end
  end
end
