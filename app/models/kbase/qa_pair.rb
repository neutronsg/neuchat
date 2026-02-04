# == Schema Information
#
# Table name: kbase_qa_pairs
#
#  id                :bigint           not null, primary key
#  answer            :text             not null
#  position          :integer          default(0)
#  question          :text             not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  created_by_id     :bigint
#  knowledge_base_id :bigint           not null
#  updated_by_id     :bigint
#
# Indexes
#
#  index_kbase_qa_pairs_on_created_by_id                   (created_by_id)
#  index_kbase_qa_pairs_on_knowledge_base_id               (knowledge_base_id)
#  index_kbase_qa_pairs_on_knowledge_base_id_and_position  (knowledge_base_id,position)
#  index_kbase_qa_pairs_on_updated_by_id                   (updated_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (knowledge_base_id => kbase_knowledge_bases.id)
#  fk_rails_...  (updated_by_id => users.id)
#
class Kbase::QaPair < ApplicationRecord
  self.table_name = 'kbase_qa_pairs'

  belongs_to :knowledge_base, class_name: 'Kbase::KnowledgeBase'
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :updated_by, class_name: 'User', optional: true

  validates :question, presence: true
  validates :answer, presence: true

  scope :ordered, -> { order(position: :asc, created_at: :asc) }

  delegate :account, to: :knowledge_base

  before_create :set_position

  private

  def set_position
    self.position ||= (knowledge_base.qa_pairs.maximum(:position) || 0) + 1
  end
end
