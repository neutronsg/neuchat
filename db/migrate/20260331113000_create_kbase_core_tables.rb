class CreateKbaseCoreTables < ActiveRecord::Migration[7.1]
  def change
    create_table :kbase_knowledge_bases do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :neuai_dataset_id
      t.string :qa_document_id
      t.text :description

      t.timestamps
    end

    add_index :kbase_knowledge_bases, [:account_id, :name], unique: true
    add_index :kbase_knowledge_bases, :neuai_dataset_id

    create_table :kbase_documents do |t|
      t.references :knowledge_base, null: false, foreign_key: { to_table: :kbase_knowledge_bases }
      t.string :neuai_document_id, null: false
      t.string :name
      t.string :remote_filename
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :updated_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :kbase_documents, :neuai_document_id
    add_index :kbase_documents, [:knowledge_base_id, :neuai_document_id], unique: true, name: 'index_kbase_documents_on_kb_and_neuai_doc'

    create_table :kbase_qa_pairs do |t|
      t.references :knowledge_base, null: false, foreign_key: { to_table: :kbase_knowledge_bases }
      t.text :question, null: false
      t.text :answer, null: false
      t.integer :position, default: 0
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :updated_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :kbase_qa_pairs, [:knowledge_base_id, :position]
  end
end
