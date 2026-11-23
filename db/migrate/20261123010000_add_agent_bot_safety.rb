class AddAgentBotSafety < ActiveRecord::Migration[7.0]
  def change
    add_column :agent_bots, :safety_mode, :string
    add_column :agent_bots, :safety_version, :bigint, null: false, default: 0
    add_check_constraint :agent_bots, "safety_mode IS NULL OR safety_mode IN ('aws','aws_shadow','custom')", name: 'agent_bot_safety_mode'
    create_table :bot_safety_changes do |t|
      t.references :account, null: false, foreign_key: true
      t.references :agent_bot, null: false, foreign_key: true
      t.bigint :user_id
      t.string :previous_mode
      t.string :mode, null: false
      t.bigint :version, null: false
      t.datetime :created_at, null: false
    end
    add_index :bot_safety_changes, [:agent_bot_id, :version], unique: true
  end
end
