class BotSafetyChange < ApplicationRecord
  belongs_to :account
  belongs_to :agent_bot
  validates :mode, inclusion: { in: %w[aws aws_shadow custom] }
end
