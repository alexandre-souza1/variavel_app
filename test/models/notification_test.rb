require "test_helper"

class NotificationTest < ActiveSupport::TestCase
  test "task assignment creates notification for assigned user" do
    task = tasks(:one)
    user = users(:two)

    assert_difference -> { user.notifications.count }, 1 do
      TaskAssignment.create!(task: task, user: user)
    end

    notification = user.notifications.recent.first

    assert_equal "task_assigned", notification.kind
    assert_equal "Nova tarefa para você", notification.title
    assert_equal task, notification.notifiable
    assert_equal task.creator, notification.actor
    assert_equal Rails.application.routes.url_helpers.action_plan_path(task.bucket.action_plan),
                 notification.action_url
  end

  test "fleet availability sent creates pdf notifications for fleet admins" do
    actor = users(:one)
    recipient = users(:two)
    recipient.update!(sector: :fleet)
    fleet_availability = fleet_availabilities(:one)

    assert_difference -> { recipient.notifications.count }, 1 do
      NotificationDelivery.fleet_availability_sent(
        fleet_availability: fleet_availability,
        actor: actor
      )
    end

    notification = recipient.notifications.recent.first

    assert_equal "fleet_availability_sent", notification.kind
    assert_equal "Baixar PDF", notification.action_text
    assert_equal Rails.application.routes.url_helpers.fleet_availability_path(
      fleet_availability,
      format: :pdf,
      download: true
    ),
                 notification.action_url
  end

  test "due soon service creates one notification for enabled task" do
    task = tasks(:one)
    recipient = users(:one)

    task.update_columns(
      completed: false,
      due_at: 12.hours.from_now,
      due_notification_enabled: true,
      due_notification_sent_at: nil
    )

    assert_difference -> { recipient.notifications.count }, 1 do
      TaskDueNotificationService.call
    end

    notification = recipient.notifications.recent.first

    assert_equal "task_due_soon", notification.kind
    assert_equal "Tarefa prestes a vencer", notification.title
    assert_equal "Abrir tarefa", notification.action_text
    assert_equal task, notification.notifiable
    assert task.reload.due_notification_sent_at.present?

    assert_no_difference -> { recipient.notifications.count } do
      TaskDueNotificationService.call
    end
  end
end
