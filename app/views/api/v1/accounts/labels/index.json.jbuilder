json.payload do
  json.array! @labels do |label|
    json.id label.id
    json.ai_category label.ai_category
    json.ai_category_name label.ai_category_name
    json.title label.title
    json.description label.description
    json.color label.color
    json.show_on_sidebar label.show_on_sidebar
  end
end
