require "test_helper"
require "minitest/mock"

class PushNotificationJobTest < ActiveJob::TestCase
  test "job never sends a notification to a device reassigned to another account" do
    notification = users(:one).notifications.create!(kind: "test", title: "Test")
    device = users(:two).push_devices.create!(token: "other", session_binding: "other", last_seen_at: Time.current)
    FirebasePush.stub(:enabled?, true) do
      FirebasePush.stub(:new, -> { flunk "Must not construct a sender for another account" }) do
        PushNotificationJob.perform_now(notification.id, device.id)
      end
    end
  end

  test "notification creation queues push for the recipients devices only" do
    device = users(:one).push_devices.create!(token: "one", session_binding: "one", last_seen_at: Time.current)
    users(:two).push_devices.create!(token: "two", session_binding: "two", last_seen_at: Time.current)
    FirebasePush.stub(:enabled?, true) do
      assert_enqueued_jobs 1, only: PushNotificationJob do
        notification = users(:one).notifications.create!(kind: "test", title: "Test")
        assert_enqueued_with(job: PushNotificationJob, args: [notification.id, device.id])
      end
    end
  end

  test "read notifications are not pushed" do
    notification = users(:one).notifications.create!(kind: "test", title: "Test", read_at: Time.current)
    device = users(:one).push_devices.create!(token: "one", session_binding: "one", last_seen_at: Time.current)
    FirebasePush.stub(:enabled?, true) do
      FirebasePush.stub(:new, -> { flunk "Read notification must not be sent" }) do
        PushNotificationJob.perform_now(notification.id, device.id)
      end
    end
  end
end
