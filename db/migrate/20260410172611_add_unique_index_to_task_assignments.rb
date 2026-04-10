class AddUniqueIndexToTaskAssignments < ActiveRecord::Migration[7.1]
  def change
    add_index :task_assignments, [:task_id, :user_id], unique: true
  end
end
