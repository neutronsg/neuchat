require 'rails_helper'

RSpec.describe Conversations::BotCategoryCatalog do
  let(:account) { create(:account) }

  it 'isolates account categories and retains stable names across title changes and disablement' do
    label = account.labels.create!(title: 'custom-topic', ai_category: true, ai_category_name: 'Custom topic', description: 'Synthetic category')
    create(:label, ai_category: true, ai_category_name: 'Other account')
    catalog = described_class.for(account)
    expect(catalog[:categories].pluck(:name)).to eq(['Custom topic'])
    label.update!(title: 'renamed-topic')
    expect(described_class.for(account)[:version]).to eq(catalog[:version])
    label.update!(ai_category: false)
    expect(described_class.for(account)[:categories]).to be_empty
    expect(label.update(ai_category_name: 'Changed')).to be false
    expect(label.destroy).to be false
    expect(label.reload.ai_category_name).to eq('Custom topic')
  end

  it 'keeps Others enabled and limits category descriptions' do
    label = account.labels.create!(title: 'others', ai_category: true, ai_category_name: 'Others')
    expect(label.update(ai_category: false)).to be false
    expect(label.update(description: 'x' * 501)).to be false
  end

  it 'validates dynamic outcomes against the account, including disabled in-flight categories' do
    account.labels.create!(title: 'custom', ai_category: false, ai_category_name: 'Custom')
    expect { Conversations::BotOutcomeContract.categories!(['Custom'], account) }.not_to raise_error
    expect { Conversations::BotOutcomeContract.categories!(['Custom'], create(:account)) }.to raise_error(ArgumentError)
    expect { Conversations::BotOutcomeContract.categories!(['Invented'], account) }.to raise_error(ArgumentError)
  end

  it 'counts Unicode code points for category names and descriptions' do
    label = account.labels.create!(title: 'unicode', ai_category: true, ai_category_name: '😀' * 100, description: '😀' * 500)
    expect(described_class.for(account)[:categories].first[:description]).to eq('😀' * 500)
    expect(label.update(description: '😀' * 501)).to be false
    invalid = account.labels.build(title: 'too-long', ai_category: true, ai_category_name: '😀' * 101)
    expect(invalid).not_to be_valid
  end
end
