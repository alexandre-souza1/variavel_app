class TaskAssignment < ApplicationRecord
  belongs_to :task
  belongs_to :user

  after_create_commit :notify_assigned_user

  private

  def notify_assigned_user
    NotificationDelivery.task_assigned(
      task: task,
      user: user,
      actor: task.creator
    )
  end
end
