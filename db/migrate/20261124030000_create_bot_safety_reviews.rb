class CreateBotSafetyReviews < ActiveRecord::Migration[7.0]
  def change
    create_table :bot_safety_review_runs do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: 'queued'
      t.jsonb :settings, null: false, default: {}
      t.jsonb :summary, null: false, default: {}
      t.datetime :cutoff_at, null: false
      t.bigint :high_water_id, null: false
      t.integer :calls_reserved, null: false, default: 0
      t.datetime :lease_until
      t.datetime :export_lease_until
      t.string :export_status
      t.timestamps
    end
    add_index :bot_safety_review_runs, [:account_id, :idempotency_key], unique: true
    create_items
    create_notes
    add_checks
  end

  private

  def create_items
    create_table :bot_safety_review_items do |t|
      t.references :bot_safety_review_run, null: false, foreign_key: true, index: { name: 'index_safety_items_run' }
      t.bigint :conversation_id, null: false
      t.bigint :message_id, null: false
      t.string :status, null: false, default: 'pending'
      t.jsonb :manifest, null: false, default: {}
      t.jsonb :result, null: false, default: {}
      t.datetime :lease_until
      t.timestamps
    end
    add_index :bot_safety_review_items, [:bot_safety_review_run_id, :message_id], unique: true, name: 'index_safety_items_unique_message'
  end

  def create_notes
    create_table :bot_safety_review_notes do |t|
      t.references :bot_safety_review_item, null: false, foreign_key: true, index: { name: 'index_safety_notes_item' }
      t.references :user, null: false, foreign_key: true
      t.string :verdict, null: false
      t.text :note, null: false
      t.timestamps
    end
  end

  def add_checks
    add_check_constraint :bot_safety_review_runs, "status IN ('queued','running','completed','incomplete','failed')", name: 'safety_review_run_status'
    states = "status IN ('pending','running','completed','insufficient_evidence','execution_error','budget_exhausted')"
    add_check_constraint :bot_safety_review_items, states, name: 'safety_review_item_status'
    add_check_constraint :bot_safety_review_runs, 'calls_reserved >= 0', name: 'safety_review_calls_positive'
  end
end
