class AddEarlyDueNotificationSentAtToTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :tasks, :early_due_notification_sent_at, :datetime
  end
end
