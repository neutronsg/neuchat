# == Schema Information
#
# Table name: kbase_documents
#
#  id                :bigint           not null, primary key
#  name              :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  created_by_id     :bigint
#  knowledge_base_id :bigint           not null
#  neuai_document_id :string           not null
#  updated_by_id     :bigint
#
# Indexes
#
#  index_kbase_documents_on_created_by_id      (created_by_id)
#  index_kbase_documents_on_kb_and_neuai_doc   (knowledge_base_id,neuai_document_id) UNIQUE
#  index_kbase_documents_on_knowledge_base_id  (knowledge_base_id)
#  index_kbase_documents_on_neuai_document_id  (neuai_document_id)
#  index_kbase_documents_on_updated_by_id      (updated_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (knowledge_base_id => kbase_knowledge_bases.id)
#  fk_rails_...  (updated_by_id => users.id)
#
class Kbase::Document < ApplicationRecord
  self.table_name = 'kbase_documents'

  belongs_to :knowledge_base, class_name: 'Kbase::KnowledgeBase'
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true

  validates :neuai_document_id, presence: true
  validates :neuai_document_id, uniqueness: { scope: :knowledge_base_id }

  scope :ordered, -> { order(created_at: :desc) }

  delegate :account, to: :knowledge_base
end
