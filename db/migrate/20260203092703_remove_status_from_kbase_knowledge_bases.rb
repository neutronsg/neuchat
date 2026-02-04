class RemoveStatusFromKbaseKnowledgeBases < ActiveRecord::Migration[7.1]
  def change
    remove_column :kbase_knowledge_bases, :status, :integer
  end
end
