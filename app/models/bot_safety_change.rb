class BotSafetyChange < ApplicationRecord
  belongs_to :account
  belongs_to :agent_bot
  validates :mode, inclusion: { in: %w[aws aws_shadow aws_custom custom hybrid hybrid_shadow dual] }
end
