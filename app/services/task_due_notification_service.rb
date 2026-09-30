class TaskDueNotificationService
  WINDOW = 24.hours
  EARLY_WINDOW = 48.hours

  def self.call(now: Time.current)
    new(now: now).call
  end

  def self.notify_if_due_soon(task, now: Time.current)
    new(now: now).notify_if_due_soon(task)
  end

  def initialize(now:)
    @now = now
  end

  def call
    eligible_tasks.find_each do |task|
      notify_if_due_soon(task)
    end
  end

  def notify_if_due_soon(task)
    return false unless due_soon?(task)

    task.with_lock do
      task.reload
      return false unless due_soon?(task)

      early = task.due_at > now + WINDOW
      NotificationDelivery.task_due_soon(task: task, early: early)
      task.update_column(notification_timestamp(task), now)
    end

    true
  end

  private

  attr_reader :now

  def eligible_tasks
    scope = Task
      .where(due_notification_enabled: true)
      .where(completed: [false, nil])
    scope.where(due_notification_sent_at: nil, due_at: now..(now + WINDOW))
      .or(scope.where(early_due_notification_sent_at: nil)
        .where("due_at > ? AND due_at <= ?", now + WINDOW, now + EARLY_WINDOW))
      .includes(:users, bucket: :action_plan)
  end

  def due_soon?(task)
    task.due_notification_enabled? &&
      !task.completed? &&
      task.due_at.present? &&
      task.due_at.between?(now, now + EARLY_WINDOW) &&
      task.public_send(notification_timestamp(task)).blank?
  end

  def notification_timestamp(task)
    task.due_at > now + WINDOW ? :early_due_notification_sent_at : :due_notification_sent_at
  end
end
