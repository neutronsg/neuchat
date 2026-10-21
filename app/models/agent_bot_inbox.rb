# == Schema Information
#
# Table name: agent_bot_inboxes
#
#  id           :bigint           not null, primary key
#  status       :integer          default("active")
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :integer
#  agent_bot_id :integer
#  inbox_id     :integer
#

class AgentBotInbox < ApplicationRecord
  validates :inbox_id, presence: true
  validates :agent_bot_id, presence: true
  before_validation :ensure_account_id
  after_update :clear_bot_idle_waits
  before_destroy :clear_bot_idle_waits

  belongs_to :inbox
  belongs_to :agent_bot
  belongs_to :account
  enum status: { active: 0, inactive: 1 }

  private

  def clear_bot_idle_waits
    Conversation.where(inbox_id: inbox_id).where.not(bot_idle_deadline_at: nil).update_all(Conversations::BotIdleState::EMPTY_STATE) # rubocop:disable Rails/SkipsModelValidations
  end

  def ensure_account_id
    self.account_id = inbox&.account_id
  end
end
