require 'rails_helper'
require 'timeout'

RSpec.describe 'Concurrent AI label management', type: :request do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:label) { create(:label, account: account) }

  after do
    account.labels.delete_all
    account.destroy!
    admin.destroy!
  end

  # Both requests fetch an ordinary label before the first writer enables it.
  # Release the second only after the first commits, preserving its stale instance.
  def hold_label_read(controller, ready, gates)
    allow(controller).to receive(:fetch_label).and_wrap_original do |original|
      original.call
      index = Thread.current[:label_review_request]
      ready << index
      gates[index].pop
    end
  end

  def request_worker(operation, index, headers)
    Thread.new do
      Thread.current[:label_review_request] = index
      ActiveRecord::Base.connection_pool.with_connection do
        session = ActionDispatch::Integration::Session.new(Rails.application)
        session.public_send(operation[0], "/api/v1/accounts/#{account.id}/labels/#{label.id}",
                            params: { label: operation[1] }, headers: headers, as: :json)
        session.response.status
      end
    end
  end

  def overlapping_requests(second_method, second_attributes)
    ready = Queue.new
    gates = [Queue.new, Queue.new]
    allow(Api::V1::Accounts::LabelsController).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap { |controller| hold_label_read(controller, ready, gates) }
    end
    operations = [[:patch, { ai_category: true, ai_category_name: 'First name' }], [second_method, second_attributes]]
    workers = operations.each_with_index.map { |operation, index| request_worker(operation, index, admin.create_new_auth_token) }
    release_in_order(ready, gates, workers)
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end

  def release_in_order(ready, gates, workers)
    Timeout.timeout(15) do
      2.times { ready.pop }
      gates[0] << true
      first_status = workers[0].value
      gates[1] << true
      [first_status, workers[1].value]
    end
  end

  it 'rejects a stale concurrent rename after the permanent category name is assigned' do
    statuses = overlapping_requests(:patch, { ai_category: true, ai_category_name: 'Second name' })
    expect(statuses).to eq([200, 422])
    expect(label.reload.ai_category_name).to eq('First name')
    expect(Conversations::BotCategoryCatalog.for(account)[:categories].pluck(:name)).to eq(['First name'])
  end

  it 'rejects a stale delete after another request enables the category' do
    statuses = overlapping_requests(:delete, {})
    expect(statuses).to eq([200, 422])
    expect(label.reload).to be_ai_category
    expect(label.ai_category_name).to eq('First name')
  end
end
