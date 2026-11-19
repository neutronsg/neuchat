class Conversations::BotCategoryCatalog
  def self.for(account)
    rows = account.labels.where(ai_category: true).order(:ai_category_name).pluck(:ai_category_name, :description)
    categories = rows.map { |name, description| { name: name, description: description.to_s } }
    { version: Digest::SHA256.hexdigest(categories.to_json), categories: categories }
  end
end
