class AddImageMessagesEnabledToChannelWhatsapp < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_whatsapp, :image_messages_enabled, :boolean, default: false, null: false
  end
end
