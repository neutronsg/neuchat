require 'tempfile'
require 'csv'
require 'zip'
require 'caxlsx'

class BotSafetyReviews::ExportJob < ApplicationJob
  queue_as :low
  HEADERS = %w[item_id message_id status ai_verdict human_verdict].freeze

  def perform(id)
    @run = BotSafetyReviewRun.find(id)
    claimed = claim
    return unless claimed

    Tempfile.create(['safety-review', '.zip']) do |file|
      write_zip(file.path)
      publish(file.path)
    end
  rescue BotSafetyReviewRun::LeaseLost
    nil
  rescue StandardError
    fail_export if claimed
  end

  private

  def publish(path)
    # Upload outside the row lock, then publish only if this worker still owns the lease.
    File.open(path) do |io|
      blob = ActiveStorage::Blob.create_and_upload!(io: io, filename: "safety-review-#{@run.id}-#{@run.created_at.utc.strftime('%Y%m%d')}.zip",
                                                    content_type: 'application/zip')
      begin
        @run.with_export_lease(@owner) do
          @run.export_file.attach(blob)
          @run.update!(export_status: 'ready', export_lease_until: nil)
        end
      rescue BotSafetyReviewRun::LeaseLost
        blob.purge
        raise
      end
    end
  end

  def claim
    @run.with_lock do
      next false unless %w[completed incomplete failed].include?(@run.status)
      next false if @run.export_lease_until&.future?

      @owner = SecureRandom.uuid
      @run.update!(export_status: 'running', export_lease_until: 10.minutes.from_now, summary: @run.summary.merge('export_owner' => @owner))
      true
    end
  end

  def fail_export
    @run.with_export_lease(@owner) { @run.update!(export_status: 'failed', export_lease_until: nil) }
  rescue BotSafetyReviewRun::LeaseLost
    nil
  end

  def write_zip(path)
    Zip::OutputStream.open(path) do |zip|
      zip.put_next_entry('manifest.json')
      zip.write({ format: 2, id: @run.id, account_id: @run.account_id, environment: ENV.fetch('OCA_BOT_SAFETY_ENVIRONMENT', 'local'),
                  settings: @run.settings, cutoff_at: @run.cutoff_at, summary: @run.summary, exported_at: Time.current,
                  note: 'AI findings require human review. Missing evidence is not a pass. JSONL contains available evidence.' }.to_json)
      write_evidence(zip)
      zip.put_next_entry('review-results.xlsx')
      zip.write(workbook.to_stream.read)
      zip.put_next_entry('summary.csv')
      zip.write(CSV.generate_line(HEADERS))
      @run.items.find_each { |item| zip.write(CSV.generate_line(summary_row(item))) }
    end
  end

  def write_evidence(zip)
    zip.put_next_entry('records.jsonl')
    total_bytes = 0
    @run.items.find_each do |item|
      data = item.as_json(only: [:id, :message_id, :status, :result, :manifest])
      data[:notes] = item.notes.order(:id).as_json(only: [:user_id, :verdict, :note, :created_at])
      line = "#{data.merge(evidence_for(item)).to_json}\n"
      total_bytes += line.bytesize
      raise ArgumentError, 'Export exceeds 50 MB; select a smaller batch' if total_bytes > 50.megabytes

      zip.write(line)
      @run.with_export_lease(@owner) { @run.update!(export_lease_until: 10.minutes.from_now) }
    end
  end

  def evidence_for(item)
    message = @run.account.messages.find(item.message_id)
    evidence = BotSafetyReviews::Evidence.call(@run, message)
    return { evidence_status: 'source_changed' } unless evidence[:manifest].deep_stringify_keys == item.manifest

    { evidence: evidence }
  rescue StandardError
    { evidence_status: 'unavailable' }
  end

  def summary_row(item)
    [item.id, item.message_id, item.status, item.result.dig('result', 'verdict'), item.notes.order(:id).last&.verdict]
  end

  def workbook
    package = Axlsx::Package.new
    package.workbook.add_worksheet(name: 'Review results') do |sheet|
      sheet.add_row HEADERS
      @run.items.find_each { |item| sheet.add_row summary_row(item), types: [:integer, :integer, :string, :string, :string] }
    end
    package
  end
end
