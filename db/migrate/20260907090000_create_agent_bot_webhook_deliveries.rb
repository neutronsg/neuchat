class CreateAgentBotWebhookDeliveries < ActiveRecord::Migration[7.1]
  def change
    create_table :agent_bot_webhook_deliveries do |t|
      t.string :delivery_key, null: false
      t.string :url, null: false
      t.string :webhook_type, null: false, default: 'agent_bot_webhook'
      t.jsonb :payload, null: false, default: {}
      t.string :status, null: false, default: 'pending'
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at, null: false
      t.datetime :locked_at
      t.datetime :delivered_at
      t.text :last_error

      t.timestamps
    end

    add_index :agent_bot_webhook_deliveries, :delivery_key, unique: true
    add_index :agent_bot_webhook_deliveries, [:status, :next_attempt_at],
              name: 'index_agent_bot_webhook_deliveries_on_ready'
    add_index :agent_bot_webhook_deliveries, :locked_at
  end
end
