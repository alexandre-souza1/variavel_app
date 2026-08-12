class TaskDueNotificationService
  WINDOW = 24.hours

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

      NotificationDelivery.task_due_soon(task: task)
      task.update_column(:due_notification_sent_at, Time.current)
    end

    true
  end

  private

  attr_reader :now

  def eligible_tasks
    Task
      .where(due_notification_enabled: true, due_notification_sent_at: nil)
      .where(completed: [false, nil])
      .where(due_at: now..(now + WINDOW))
      .includes(:users, bucket: :action_plan)
  end

  def due_soon?(task)
    task.due_notification_enabled? &&
      task.due_notification_sent_at.blank? &&
      !task.completed? &&
      task.due_at.present? &&
      task.due_at.between?(now, now + WINDOW)
  end
end
