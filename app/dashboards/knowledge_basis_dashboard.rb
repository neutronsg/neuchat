require 'administrate/base_dashboard'

# Dashboard for Kbase::KnowledgeBase
# Note: Rails inflects "knowledge_base" singular as "knowledge_basis"
class KnowledgeBasisDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String,
    account: Field::BelongsTo,
    neuai_dataset_id: Field::String,
    status: Field::String
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    account
    status
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    account
    neuai_dataset_id
    status
  ].freeze

  FORM_ATTRIBUTES = %i[
    name
    account
    neuai_dataset_id
  ].freeze

  def self.model
    Kbase::KnowledgeBase
  end
end
