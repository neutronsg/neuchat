# Business category names remain human-readable; NeuChat labels use valid stable slugs.
class Conversations::BotCategoryLabels
  def self.sync!(conversation, categories)
    titles = categories.sort.map do |category|
      existing = conversation.account.labels.find_by(ai_category_name: category)
      next existing.title if existing

      title = category.downcase.gsub(/[^a-z0-9]+/, '-').delete_suffix('-')
      ensure_label(conversation.account, title, category).title
    end
    # Replace only the legacy raw category tags recorded by this bot, preserving manual labels.
    conversation.update!(label_list: ((conversation.label_list - categories) + titles).uniq)
  end

  def self.ensure_label(account, title, category)
    account.labels.find_or_create_by!(title: title) do |label|
      label.description = "AI enquiry category: #{category}"
      label.color = '#3b82f6'
      label.show_on_sidebar = true
    end
  rescue ActiveRecord::RecordInvalid => e
    # Another conversation may register the same account label between lookup and validation.
    raise unless e.record.errors.details[:title].any? { |error| error[:error] == :taken }

    account.labels.find_by!(title: title)
  end
end
