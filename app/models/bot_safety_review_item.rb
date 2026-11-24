class BotSafetyReviewItem < ApplicationRecord
  belongs_to :bot_safety_review_run
  has_many :notes, class_name: 'BotSafetyReviewNote', dependent: :destroy
  validates :status, inclusion: { in: %w[pending running completed insufficient_evidence execution_error budget_exhausted] }
end
