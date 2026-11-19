# == Schema Information
#
# Table name: labels
#
#  id              :bigint           not null, primary key
#  color           :string           default("#1f93ff"), not null
#  description     :text
#  show_on_sidebar :boolean
#  title           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint
#
# Indexes
#
#  index_labels_on_account_id            (account_id)
#  index_labels_on_title_and_account_id  (title,account_id) UNIQUE
#
class Label < ApplicationRecord
  include RegexHelper
  include AccountCacheRevalidator

  belongs_to :account

  validates :title,
            presence: { message: I18n.t('errors.validations.presence') },
            format: { with: UNICODE_CHARACTER_NUMBER_HYPHEN_UNDERSCORE },
            uniqueness: { scope: :account_id }

  validates :ai_category_name, presence: true, if: :ai_category?
  validates :ai_category_name, length: { maximum: 100 }, uniqueness: { scope: :account_id }, allow_nil: true
  validates :description, length: { maximum: 500 }, if: :ai_category?
  validate :stable_ai_category
  validate :ai_category_capacity
  before_destroy :retain_ai_category

  def stable_ai_category
    if persisted? && ai_category_name_in_database.present? && ai_category_name_changed?
      errors.add(:ai_category_name, 'cannot change; disable this category and create another')
    end
    errors.add(:ai_category, 'Others must remain enabled') if ai_category_name == 'Others' && !ai_category?
  end

  def ai_category_capacity
    return unless ai_category? && (!persisted? || !ai_category_in_database)
    return if account.labels.where(ai_category: true).count < 100

    errors.add(:ai_category, 'at most 100 active categories are supported')
  end

  def retain_ai_category
    return if ai_category_name.blank?

    errors.add(:base, 'Disable AI categories instead of deleting them to preserve historical reports')
    throw :abort
  end

  after_update_commit :update_associated_models
  default_scope { order(:title) }

  before_validation do
    self.title = title.downcase if attribute_present?('title')
  end

  def conversations
    account.conversations.tagged_with(title)
  end

  def messages
    account.messages.where(conversation_id: conversations.pluck(:id))
  end

  def reporting_events
    account.reporting_events.where(conversation_id: conversations.pluck(:id))
  end

  private

  def update_associated_models
    return unless title_previously_changed?

    Labels::UpdateJob.perform_later(title, title_previously_was, account_id)
  end
end
