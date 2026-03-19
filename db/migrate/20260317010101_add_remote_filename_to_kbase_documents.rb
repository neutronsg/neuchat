class AddRemoteFilenameToKbaseDocuments < ActiveRecord::Migration[7.1]
  def change
    add_column :kbase_documents, :remote_filename, :string
  end
end
