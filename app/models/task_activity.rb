class TaskActivity < ApplicationRecord
  belongs_to :task
  belongs_to :user

  after_create_commit :broadcast_activity

  enum :activity_type, {
    created: "created",
    updated: "updated",
    completed: "completed",
    reopened: "reopened",
    due_date_changed: "due_date_changed",
    start_date_changed: "start_date_changed",
    description_changed: "description_changed",
    bucket_changed: "bucket_changed",
    assignee_added: "assignee_added",
    assignee_removed: "assignee_removed",
    label_added: "label_added",
    label_removed: "label_removed",
    checklist_item_added: "checklist_item_added",
    checklist_item_completed: "checklist_item_completed"
  }

  def broadcast_activity
    broadcast_append_to(
      "task_feed_#{task.id}",
      target: "task_feed_#{task.id}",
      partial: "task_activities/activity",
      locals: { activity: self }
    )
  end
end
