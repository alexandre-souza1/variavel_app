class PushNotificationJob < ApplicationJob
  queue_as :default
  retry_on FirebasePush::DeliveryError, FirebasePush::ConfigurationError,
           Net::OpenTimeout, Net::ReadTimeout, SocketError, wait: :polynomially_longer, attempts: 5

  def perform(notification_id, device_id)
    return unless FirebasePush.enabled?
    notification = Notification.find_by(id: notification_id)
    return unless notification && notification.user.active? && !notification.read?
    device = notification.user.push_devices.find_by(id: device_id)
    return unless device

    FirebasePush.new.deliver(notification: notification, device: device)
  end
end
