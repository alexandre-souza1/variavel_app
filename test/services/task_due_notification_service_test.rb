require "test_helper"

class TaskDueNotificationServiceTest < ActiveSupport::TestCase
  setup do
    users(:one).update!(name: "User One")
    @now = Time.zone.local(2026, 10, 1, 10)
    @task = tasks(:one)
    @task.update_columns(completed: false, due_at: @now + 48.hours,
                         due_notification_enabled: true, due_notification_sent_at: nil,
                         early_due_notification_sent_at: nil)
  end

  test "sends one early reminder and another at 24 hours without duplicates" do
    assert_no_difference -> { Notification.count } do
      TaskDueNotificationService.call(now: @now - 1.second)
    end

    assert_difference -> { Notification.count }, 1 do
      TaskDueNotificationService.call(now: @now)
    end
    assert_equal @now, @task.reload.early_due_notification_sent_at
    assert_nil @task.due_notification_sent_at
    assert_includes users(:one).notifications.recent.first.body, "próximas 48 horas"

    assert_no_difference -> { Notification.count } do
      TaskDueNotificationService.call(now: @now + 23.hours)
    end
    assert_difference -> { Notification.count }, 1 do
      TaskDueNotificationService.call(now: @now + 24.hours)
    end
    assert_equal @now + 24.hours, @task.reload.due_notification_sent_at
    assert_no_difference -> { Notification.count } do
      TaskDueNotificationService.call(now: @now + 25.hours)
    end
  end

  test "a first check within 24 hours sends only the urgent reminder" do
    assert_difference -> { Notification.count }, 1 do
      TaskDueNotificationService.call(now: @now + 36.hours)
    end
    assert_nil @task.reload.early_due_notification_sent_at
    assert @task.due_notification_sent_at.present?
    assert_no_difference -> { Notification.count } do
      TaskDueNotificationService.call(now: @now + 37.hours)
    end
  end

  test "skips disabled completed and overdue tasks" do
    [{ due_notification_enabled: false }, { completed: true }, { due_at: @now - 1.second }].each do |attributes|
      @task.update_columns({ due_notification_enabled: true, completed: false, due_at: @now + 36.hours }.merge(attributes))
      assert_no_difference -> { Notification.count } do
        TaskDueNotificationService.call(now: @now)
        assert_not TaskDueNotificationService.notify_if_due_soon(@task, now: @now)
      end
    end
  end

  test "changing the deadline resets both reminders and saving triggers the early reminder" do
    travel_to @now do
      @task.update_columns(due_notification_sent_at: @now - 1.day, early_due_notification_sent_at: @now - 2.days)
      @task.update!(due_at: @now + 72.hours)
      assert_nil @task.reload.due_notification_sent_at
      assert_nil @task.early_due_notification_sent_at

      assert_difference -> { Notification.count }, 1 do
        @task.update!(due_at: @now + 36.hours)
      end
      assert_equal @now, @task.reload.early_due_notification_sent_at
      assert_nil @task.due_notification_sent_at

      @task.update!(due_notification_enabled: false)
      assert_nil @task.reload.early_due_notification_sent_at
      assert_nil @task.due_notification_sent_at
    end
  end
end
