class AddWechatChannel < ActiveRecord::Migration[6.1]
  def change
    create_table "channel_wechat" do |t|
      t.string "app_id", null: false
      t.string "app_secret", null: false
      t.string "token", null: false
      t.string "encoding_aes_key"
      t.string "app_name"
      t.integer "account_id", null: false
      t.timestamps

      t.index ["app_id"], name: "index_channel_wechat_on_app_id", unique: true
      t.index ["account_id"], name: "index_channel_wechat_on_account_id"
    end
  end
end
