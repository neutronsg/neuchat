class AddBotIdleState < ActiveRecord::Migration[7.1]
  def change
    add_column :agent_bots, :idle_protocol_seen_at, :datetime
    add_column :conversations, :bot_idle_deadline_at, :datetime
    add_column :conversations, :bot_idle_reply_id, :bigint
    add_column :conversations, :bot_idle_agent_bot_id, :bigint
    add_index :conversations, :bot_idle_deadline_at, where: 'bot_idle_deadline_at IS NOT NULL'
    add_index :conversations, :bot_idle_agent_bot_id, where: 'bot_idle_agent_bot_id IS NOT NULL'
  end
end
