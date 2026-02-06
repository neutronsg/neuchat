# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Kbase::QaPair, type: :model do
  describe '.ordered' do
    it 'returns newest records first by created_at' do
      account = create(:account)
      knowledge_base = Kbase::KnowledgeBase.create!(
        account: account,
        name: 'Test KB'
      )

      older = nil
      newer = nil

      travel_to 2.days.ago do
        older = described_class.create!(
          knowledge_base: knowledge_base,
          question: 'Old question',
          answer: 'Old answer'
        )
      end

      travel_to 1.day.ago do
        newer = described_class.create!(
          knowledge_base: knowledge_base,
          question: 'New question',
          answer: 'New answer'
        )
      end

      expect(knowledge_base.qa_pairs.ordered.pluck(:id)).to eq([newer.id, older.id])
    end
  end
end
