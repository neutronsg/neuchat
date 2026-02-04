class CreateKbaseTables < ActiveRecord::Migration[7.1]
  def change
    create_table :kbase_knowledge_bases do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :neuai_dataset_id
      t.string :qa_document_id
      t.text :description
      t.integer :status, default: 0

      t.timestamps
    end

    add_index :kbase_knowledge_bases, [:account_id, :name], unique: true
    add_index :kbase_knowledge_bases, :neuai_dataset_id

    create_table :kbase_documents do |t|
      t.references :knowledge_base, null: false, foreign_key: { to_table: :kbase_knowledge_bases }
      t.string :neuai_document_id, null: false
      t.string :name

      t.timestamps
    end

    add_index :kbase_documents, :neuai_document_id

    create_table :kbase_qa_pairs do |t|
      t.references :knowledge_base, null: false, foreign_key: { to_table: :kbase_knowledge_bases }
      t.text :question, null: false
      t.text :answer, null: false
      t.integer :position, default: 0

      t.timestamps
    end

    add_index :kbase_qa_pairs, [:knowledge_base_id, :position]
  end
end
