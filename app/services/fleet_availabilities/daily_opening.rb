module FleetAvailabilities
  class DailyOpening
    Result = Data.define(
      :availability,
      :locked_count,
      :skipped_reason
    )

    def self.call(user: nil, now: Time.current)
      new(user: user, now: now).call
    end

    def initialize(user:, now:)
      @user = user || User.order(:id).first
      @now = now.in_time_zone
    end

    def call
      locked_count = FleetAvailability.auto_lock_expired!(now: @now)

      return skipped_result(locked_count, :missing_user) unless @user

      next_date = @now.to_date.next_day
      setting = FleetAvailabilitySetting.current

      return skipped_result(locked_count, :before_opening) unless opening_time_reached?(setting)
      return skipped_result(locked_count, :sunday) if next_date.sunday?

      dimensioning = FleetAvailability.dimensioning_period_for(next_date)

      return skipped_result(locked_count, :missing_dimensioning) unless dimensioning

      availability = find_or_create_next_availability(
        next_date: next_date,
        dimensioning: dimensioning
      )

      Result.new(
        availability,
        locked_count,
        nil
      )
    end

    private

    def opening_time_reached?(setting)
      @now >= setting.auto_open_at(@now.to_date)
    end

    def find_or_create_next_availability(next_date:, dimensioning:)
      existing = FleetAvailability.find_by(date: next_date)

      return existing if existing

      FleetAvailabilities::Creator.call(
        user: @user,
        date: next_date,
        agreed_quantity: dimensioning.route_quantity,
        special_routes: dimensioning.special_routes,
        copy_previous_day: true
      )
    end

    def skipped_result(locked_count, reason)
      Result.new(nil, locked_count, reason)
    end
  end
end
