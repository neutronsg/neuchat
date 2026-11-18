class CreateBotConversationOutcomes < ActiveRecord::Migration[7.1]
  def change
    create_table :bot_conversation_outcomes do |t|
      t.references :conversation, null: false, index: { unique: true }, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.bigint :last_message_id, null: false, default: 0
      t.bigint :evaluated_input_id, null: false, default: 0
      t.jsonb :categories, null: false, default: []
      t.jsonb :enquiries, null: false, default: []
      t.jsonb :escalations, null: false, default: []
      t.datetime :escalated_at
      t.datetime :closed_at
      t.boolean :all_solved, null: false, default: false
      t.timestamps
    end
    add_index :bot_conversation_outcomes, [:account_id, :created_at]
  end
end
