class AllowDeletedSafetyReviewAuthors < ActiveRecord::Migration[7.0]
  def change
    change_column_null :bot_safety_review_notes, :user_id, true
  end
end
