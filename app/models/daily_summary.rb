class DailySummary < ApplicationRecord
  TIME_ZONE = "Brasilia".freeze
  DELIVERY_HOUR = 8
  LEASE_DURATION = 5.minutes

  belongs_to :user
  has_one :notification, as: :notifiable, dependent: :nullify

  enum :status, { pending: 0, processing: 1, delivered: 2, queued: 3 }

  validates :summary_date, :next_attempt_at, presence: true
  validates :content, presence: true, if: :delivered?

  def self.delivery_time(date)
    Time.find_zone!(TIME_ZONE).local(date.year, date.month, date.day, DELIVERY_HOUR)
  end

  def self.next_delivery(after: Time.current)
    date = after.in_time_zone(TIME_ZONE).to_date
    loop do
      scheduled_time = delivery_time(date)
      return scheduled_time if !date.sunday? && scheduled_time > after

      date = date.next_day
    end
  end

  def eligible?(now: Time.current)
    user.active? && user.daily_summary_enabled? &&
      !summary_date.sunday? &&
      user.daily_summary_next_run_at.present? && user.daily_summary_next_run_at <= now &&
      summary_date == now.in_time_zone(TIME_ZONE).to_date && now >= self.class.delivery_time(summary_date)
  end
end
