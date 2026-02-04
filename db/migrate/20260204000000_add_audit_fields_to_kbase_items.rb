class AddAuditFieldsToKbaseItems < ActiveRecord::Migration[7.1]
  def change
    add_reference :kbase_documents, :created_by,
                  foreign_key: { to_table: :users }, index: true
    add_reference :kbase_documents, :updated_by,
                  foreign_key: { to_table: :users }, index: true

    add_reference :kbase_qa_pairs, :created_by,
                  foreign_key: { to_table: :users }, index: true
    add_reference :kbase_qa_pairs, :updated_by,
                  foreign_key: { to_table: :users }, index: true
  end
end
