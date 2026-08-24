class Notification < ApplicationRecord
  attr_accessor :skip_destroy_broadcast

  belongs_to :user
  belongs_to :actor,
             class_name: "User",
             optional: true
  belongs_to :notifiable,
             polymorphic: true,
             optional: true

  validates :kind,
            :title,
            presence: true

  scope :recent, -> { order(created_at: :desc) }
  scope :unread, -> { where(read_at: nil) }

  after_create_commit :broadcast_to_user
  after_update_commit :broadcast_to_user, if: :saved_change_to_read_at?
  after_destroy_commit :broadcast_to_user, unless: :skip_destroy_broadcast?

  def read?
    read_at.present?
  end

  def mark_as_read!
    update!(read_at: Time.current) unless read?
  end

  private

  def skip_destroy_broadcast?
    skip_destroy_broadcast == true
  end

  def broadcast_to_user
    Turbo::StreamsChannel.broadcast_replace_to(
      stream_name,
      target: "notifications-menu",
      partial: "notifications/menu",
      locals: { user: user }
    )
  end

  def stream_name
    "notifications_user_#{user_id}"
  end
end
