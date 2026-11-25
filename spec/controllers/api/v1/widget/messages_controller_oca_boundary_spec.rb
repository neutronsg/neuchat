require 'rails_helper'
RSpec.describe Api::V1::Widget::MessagesController, type: :controller do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:old) { create(:conversation, account: account, inbox: inbox, status: :resolved) }

  before do
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('OCA_BOT_REPORTS_ENABLED').and_return('true')
    allow(ENV).to receive(:[]).with('OCA_BOT_ACCOUNT_ID').and_return(account.id.to_s)
    allow(controller).to receive_messages(inbox: inbox, conversation: old)
    allow(inbox).to receive(:active_bot?).and_return(true)
  end

  it 'creates a new conversation after closing an OCA bot conversation' do
    expect(controller).to receive(:create_conversation)
    controller.send(:set_conversation)
  end

  it 'starts a new bot conversation even when reports are disabled' do
    allow(ENV).to receive(:[]).with('OCA_BOT_REPORTS_ENABLED').and_return('false')
    expect(controller).to receive(:create_conversation)
    controller.send(:set_conversation)
  end

  it 'does not replace resolved conversations without an active bot' do
    allow(inbox).to receive(:active_bot?).and_return(false)
    expect(controller).not_to receive(:create_conversation)
    controller.send(:set_conversation)
  end

  it 'does not create another conversation while pending or for other deployments' do
    old.update!(status: :pending)
    expect(controller).not_to receive(:create_conversation)
    controller.send(:set_conversation)
    old.update!(status: :resolved)
    allow(ENV).to receive(:[]).with('OCA_BOT_ACCOUNT_ID').and_return('other-account')
    controller.send(:set_conversation)
  end
end
