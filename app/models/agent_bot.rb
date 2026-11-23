# == Schema Information
#
# Table name: agent_bots
#
#  id           :bigint           not null, primary key
#  bot_config   :jsonb
#  bot_type     :integer          default("webhook")
#  description  :string
#  name         :string
#  outgoing_url :string
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint
#
# Indexes
#
#  index_agent_bots_on_account_id  (account_id)
#

class AgentBot < ApplicationRecord
  include AccessTokenable
  include Avatarable

  has_many :agent_bot_inboxes, dependent: :destroy_async
  has_many :inboxes, through: :agent_bot_inboxes
  has_many :messages, as: :sender, dependent: :nullify
  has_many :bot_safety_changes, dependent: :delete_all
  belongs_to :account, optional: true
  enum bot_type: { webhook: 0 }

  validates :outgoing_url, length: { maximum: Limits::URL_LENGTH_LIMIT }
  validates :safety_mode, inclusion: { in: %w[aws aws_shadow aws_custom custom] }, allow_nil: true
  before_save :increment_safety_version, if: :will_save_change_to_safety_mode?
  after_update :cancel_idle_waits_when_disabled
  after_save :record_safety_change, if: :saved_change_to_safety_mode?

  def increment_safety_version
    self.safety_version += 1
  end

  def record_safety_change
    return if safety_mode.nil?

    bot_safety_changes.create!(account_id: account_id, user_id: Current.user&.id,
                               previous_mode: safety_mode_before_last_save, mode: safety_mode, version: safety_version)
  end

  store_accessor :bot_config, :idle_auto_resolve_enabled, :idle_auto_resolve_after
  validates :idle_auto_resolve_enabled, inclusion: { in: [true, false, nil] }
  validates :idle_auto_resolve_after, numericality: { only_integer: true, greater_than_or_equal_to: 10, less_than: 1440 },
                                      if: -> { idle_auto_resolve_enabled == true }

  def idle_auto_resolve?
    idle_auto_resolve_enabled == true && idle_auto_resolve_after.to_i.between?(10, 1439)
  end

  def cancel_idle_waits_when_disabled
    return if idle_auto_resolve? || !saved_change_to_bot_config?

    Conversation.where(bot_idle_agent_bot_id: id).update_all(Conversations::BotIdleState::EMPTY_STATE) # rubocop:disable Rails/SkipsModelValidations
  end

  def available_name
    name
  end

  def push_event_data(inbox = nil)
    {
      id: id,
      name: name,
      avatar_url: avatar_url || inbox&.avatar_url,
      type: 'agent_bot'
    }
  end

  def webhook_data
    {
      id: id,
      name: name,
      type: 'agent_bot'
    }
  end

  def system_bot?
    account.nil?
  end
end
