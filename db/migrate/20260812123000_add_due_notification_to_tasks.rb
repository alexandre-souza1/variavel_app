class AddDueNotificationToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :due_notification_enabled, :boolean, null: false, default: false
    add_column :tasks, :due_notification_sent_at, :datetime

    add_index :tasks,
              [:due_notification_enabled, :due_notification_sent_at, :due_at],
              name: "index_tasks_on_due_notification_status"
  end
end
