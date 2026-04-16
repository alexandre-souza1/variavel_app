class AddRecurrenceToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :recurrence, :string
  end
end
