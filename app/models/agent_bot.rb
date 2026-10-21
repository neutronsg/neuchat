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
  belongs_to :account, optional: true
  enum bot_type: { webhook: 0 }

  validates :outgoing_url, length: { maximum: Limits::URL_LENGTH_LIMIT }

  store_accessor :bot_config, :idle_auto_resolve_enabled, :idle_auto_resolve_after
  validates :idle_auto_resolve_enabled, inclusion: { in: [true, false, nil] }
  validates :idle_auto_resolve_after, numericality: { only_integer: true, greater_than_or_equal_to: 10, less_than: 1440 },
                                      if: -> { idle_auto_resolve_enabled == true }
  after_update :cancel_idle_waits_when_disabled

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
