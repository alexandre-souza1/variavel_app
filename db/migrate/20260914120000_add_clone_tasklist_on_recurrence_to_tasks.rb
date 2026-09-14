class AddCloneTasklistOnRecurrenceToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :clone_tasklist_on_recurrence, :boolean, null: false, default: false
  end
end
