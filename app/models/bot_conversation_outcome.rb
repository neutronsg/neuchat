class BotConversationOutcome < ApplicationRecord
  belongs_to :conversation
  belongs_to :account
  validates :conversation_id, uniqueness: true

  def snapshot
    { categories: categories, enquiries: enquiries, escalations: escalations, all_solved: all_solved }
  end
end
