class AddFieldsToTaskActivities < ActiveRecord::Migration[7.1]
  def change
    add_reference :task_activities, :task, null: false, foreign_key: true
    add_reference :task_activities, :user, null: false, foreign_key: true
    add_column :task_activities, :activity_type, :string
    add_column :task_activities, :old_value, :text
    add_column :task_activities, :new_value, :text
    add_column :task_activities, :metadata, :jsonb
  end
end
