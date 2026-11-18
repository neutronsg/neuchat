class AddBotOutcomeDeliveryEvidence < ActiveRecord::Migration[7.1]
  def change
    add_column :bot_conversation_outcomes, :last_reply_assessed, :boolean, default: false, null: false
    add_column :bot_conversation_outcomes, :enquiry_message_ids, :jsonb, default: {}, null: false
  end
end
