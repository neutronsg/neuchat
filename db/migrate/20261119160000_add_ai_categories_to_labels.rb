class AddAiCategoriesToLabels < ActiveRecord::Migration[7.1]
  def up
    add_column :labels, :ai_category, :boolean, default: false, null: false
    add_column :labels, :ai_category_name, :string
    add_index :labels, [:account_id, :ai_category_name], unique: true
    account_id = ENV.fetch('OCA_BOT_ACCOUNT_ID', '').to_i
    return unless account_id.positive? && select_value("SELECT id FROM accounts WHERE id = #{account_id}")

    names = ['Sign-up/login', 'Learning related', 'CMS portal', 'LMS portal', 'Other apps', 'Data migration', 'App download', 'Suggestions',
             'MAX points related', 'Notifications related', 'Rewards', 'CR points related', 'Learning Terminal related', 'Awards Terminal related',
             'Allocation management', 'Reports', 'Community Terminal related', 'Leaderboard', 'Home page', 'Android version',
             'Dashboards', 'Airport 101', 'QR code scanner', 'Others']
    names.each do |name|
      title = name.downcase.gsub(/[^a-z0-9]+/, '-').delete_suffix('-')
      execute <<~SQL.squish
        INSERT INTO labels(account_id,title,description,color,show_on_sidebar,ai_category,ai_category_name,created_at,updated_at)
        VALUES(#{account_id},#{quote(title)},#{quote("AI enquiry category: #{name}")},'#3b82f6',true,true,#{quote(name)},NOW(),NOW())
        ON CONFLICT(account_id,title) DO UPDATE SET ai_category=true, ai_category_name=EXCLUDED.ai_category_name
      SQL
    end
  end

  def down
    remove_index :labels, [:account_id, :ai_category_name]
    remove_column :labels, :ai_category_name
    remove_column :labels, :ai_category
  end
end
