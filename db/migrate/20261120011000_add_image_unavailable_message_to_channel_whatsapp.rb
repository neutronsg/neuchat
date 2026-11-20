class AddImageUnavailableMessageToChannelWhatsapp < ActiveRecord::Migration[7.1]
  def change
    add_column :channel_whatsapp, :image_unavailable_message, :text
  end
end
