require 'rails_helper'

RSpec.describe Conversations::BotCategoryLabels do
  let(:conversation) { create(:conversation) }

  it 'registers valid account labels and tags so native label reports can count categories' do
    described_class.sync!(conversation, ['Sign-up/login', 'Learning related'])
    expect(conversation.account.labels.pluck(:title)).to contain_exactly('sign-up-login', 'learning-related')
    expect(conversation.reload.label_list).to contain_exactly('sign-up-login', 'learning-related')
    report = V2::Reports::LabelSummaryBuilder.new(account: conversation.account, params: {}).build
    expect(report.pluck(:conversations_count)).to eq([1, 1])
  end

  it 'is idempotent, preserves manual labels and replaces legacy raw bot categories' do
    conversation.update!(label_list: ['manual', 'Sign-up/login'])
    2.times { described_class.sync!(conversation, ['Sign-up/login']) }
    expect(conversation.reload.label_list).to contain_exactly('manual', 'sign-up-login')
    expect(conversation.account.labels.count).to eq(1)
  end

  it 'keeps registered labels in their own account and never overwrites existing label settings' do
    label = conversation.account.labels.create!(title: 'learning-related', color: '#123456', description: 'Owned by admin')
    other = create(:conversation)
    described_class.sync!(conversation, ['Learning related'])
    described_class.sync!(other, ['Learning related'])
    expect(label.reload.description).to eq('Owned by admin')
    expect(label.color).to eq('#123456')
    expect(other.account.labels.pluck(:id)).not_to include(label.id)
  end
end
