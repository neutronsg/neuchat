class AddUniqueIndexToKbaseDocuments < ActiveRecord::Migration[7.1]
  def change
    add_index :kbase_documents, [:knowledge_base_id, :neuai_document_id], unique: true, name: 'index_kbase_documents_on_kb_and_neuai_doc'
  end
end
