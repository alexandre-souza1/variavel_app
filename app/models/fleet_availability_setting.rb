class FleetAvailabilitySetting < ApplicationRecord
  DEFAULT_AUTO_LOCK_TIME = "08:00".freeze
  DEFAULT_AUTO_OPEN_TIME = "08:00".freeze

  validates :auto_lock_time, :auto_open_time, presence: true
  validate :times_are_valid

  def self.current
    first_or_create!(
      auto_lock_time: DEFAULT_AUTO_LOCK_TIME,
      auto_open_time: DEFAULT_AUTO_OPEN_TIME
    )
  end

  def auto_lock_at(date)
    time_at(date, auto_lock_time)
  end

  def auto_open_at(date)
    time_at(date, auto_open_time)
  end

  def normalized_time(value)
    return value.strftime("%H:%M") if value.respond_to?(:strftime)

    value.to_s.first(5)
  end

  private

  def time_at(date, value)
    hour, minute = normalized_time(value).split(":").map(&:to_i)

    date
      .in_time_zone
      .change(hour: hour, min: minute, sec: 0)
  end

  def times_are_valid
    validate_time_format(:auto_lock_time)
    validate_time_format(:auto_open_time)
  end

  def validate_time_format(attribute)
    raw_time = public_send("#{attribute}_before_type_cast")

    return if raw_time.to_s.match?(/\A(?:[01]\d|2[0-3]):[0-5]\d\z/)

    errors.add(attribute, "deve estar no formato HH:MM")
  end
end
