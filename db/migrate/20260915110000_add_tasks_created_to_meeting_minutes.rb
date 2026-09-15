class AddTasksCreatedToMeetingMinutes < ActiveRecord::Migration[7.1]
  def change
    add_column :meeting_minutes, :tasks_created, :boolean, null: false, default: false
  end
end
