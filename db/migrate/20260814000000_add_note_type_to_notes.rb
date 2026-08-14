class AddNoteTypeToNotes < ActiveRecord::Migration[7.1]
  def change
    add_column :notes, :note_type, :integer, default: 0, null: false
    add_index :notes, [:contact_id, :note_type, :created_at]
  end
end
