class BotSafetyReviewRun < ApplicationRecord
  belongs_to :account
  belongs_to :user, optional: true
  has_many :items, class_name: 'BotSafetyReviewItem', dependent: :destroy
  has_one_attached :export_file
  class LeaseLost < StandardError; end

  def with_review_lease(owner)
    with_lock do
      raise LeaseLost unless summary['lease_owner'] == owner

      yield
    end
  end

  def with_export_lease(owner)
    with_lock do
      raise LeaseLost unless summary['export_owner'] == owner

      yield
    end
  end

  def resumable?
    status != 'completed' && !lease_until&.future? && !export_lease_until&.future?
  end

  validates :idempotency_key, presence: true, uniqueness: { scope: :account_id }
  validates :status, inclusion: { in: %w[queued running completed incomplete failed] }
end
