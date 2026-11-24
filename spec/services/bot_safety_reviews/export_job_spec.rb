require 'rails_helper'

RSpec.describe BotSafetyReviews::ExportJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation) }
  let(:run) do
    BotSafetyReviewRun.create!(account: account, idempotency_key: 'export-test', cutoff_at: Time.current, high_water_id: message.id,
                               status: 'completed')
  end

  it 'exports XLSX and JSONL and labels changed or deleted evidence instead of substituting current text' do
    run.items.create!(conversation_id: conversation.id, message_id: message.id, status: 'completed', manifest: { hash: 'old' })
    allow(BotSafetyReviews::Evidence).to receive(:call).and_return({ manifest: { hash: 'new' }, transcript: ['MUST NOT SUBSTITUTE'] })
    described_class.perform_now(run.id)
    expect(run.reload.export_status).to eq('ready')
    Zip::File.open_buffer(run.export_file.download) do |zip|
      expect(zip.map(&:name)).to include('records.jsonl', 'review-results.xlsx', 'manifest.json')
      text = zip.read('records.jsonl')
      expect(text).to include('source_changed')
      expect(text).not_to include('MUST NOT SUBSTITUTE')
      Zip::File.open_buffer(zip.read('review-results.xlsx')) { |xlsx| expect(xlsx.map(&:name)).to include('xl/workbook.xml') }
    end
  end

  it 'prevents an expired export worker from renewing or publishing after takeover' do
    old = described_class.new
    old.instance_variable_set(:@run, run)
    expect(old.send(:claim)).to be(true)
    old_owner = old.instance_variable_get(:@owner)
    run.update!(export_lease_until: 1.minute.ago)
    replacement = described_class.new
    replacement.instance_variable_set(:@run, run)
    expect(replacement.send(:claim)).to be(true)
    new_owner = replacement.instance_variable_get(:@owner)
    expect { run.with_export_lease(old_owner) { run.update!(export_status: 'ready') } }.to raise_error(BotSafetyReviewRun::LeaseLost)
    old.send(:fail_export)
    expect(run.reload.summary['export_owner']).to eq(new_owner)
    expect(run.export_status).to eq('running')
  end
end
