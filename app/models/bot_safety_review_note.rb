class BotSafetyReviewNote < ApplicationRecord
  belongs_to :bot_safety_review_item
  belongs_to :user, optional: true
  validates :verdict, inclusion: { in: %w[correct false_positive false_negative insufficient_evidence observing] }
  validates :note, length: { minimum: 1, maximum: 4000 }
end
