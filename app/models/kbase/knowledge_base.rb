# == Schema Information
#
# Table name: kbase_knowledge_bases
#
#  id               :bigint           not null, primary key
#  description      :text
#  name             :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  neuai_dataset_id :string
#  qa_document_id   :string
#
# Indexes
#
#  index_kbase_knowledge_bases_on_account_id           (account_id)
#  index_kbase_knowledge_bases_on_account_id_and_name  (account_id,name) UNIQUE
#  index_kbase_knowledge_bases_on_neuai_dataset_id     (neuai_dataset_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Kbase::KnowledgeBase < ApplicationRecord
  self.table_name = 'kbase_knowledge_bases'

  belongs_to :account
  has_many :documents, class_name: 'Kbase::Document', dependent: :delete_all
  has_many :qa_pairs, class_name: 'Kbase::QaPair', dependent: :delete_all

  validates :name, presence: true, length: { maximum: 100 }
  validates :name, uniqueness: { scope: :account_id }
  validates :account_id, presence: true

  scope :ordered, -> { order(created_at: :desc) }
end
