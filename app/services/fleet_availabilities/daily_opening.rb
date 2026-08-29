module FleetAvailabilities
  class DailyOpening
    Result = Data.define(:availability, :locked_count, :skipped_reason)

    def self.call(user: nil, now: Time.current)
      new(user: user, now: now).call
    end

    def initialize(user:, now:)
      @user = user || User.order(:id).first
      @now = now
    end

    def call
      locked_count = FleetAvailability.auto_lock_expired!(now: @now)
      next_date = @now.to_date + 1.day
      setting = FleetAvailabilitySetting.current

      return Result.new(nil, locked_count, :before_opening) if @now < setting.auto_open_at(@now.to_date)

      return Result.new(nil, locked_count, :sunday) if next_date.sunday?
      return Result.new(nil, locked_count, :missing_user) unless @user

      dimensioning = FleetAvailability.dimensioning_period_for(next_date)
      return Result.new(nil, locked_count, :missing_dimensioning) unless dimensioning

      availability = FleetAvailability.find_or_initialize_by(date: next_date)
      if availability.new_record?
        availability = FleetAvailabilities::Creator.call(
          user: @user,
          date: next_date,
          agreed_quantity: dimensioning.route_quantity,
          special_routes: dimensioning.special_routes,
          copy_previous_day: true
        )
      end

      Result.new(availability, locked_count, nil)
    end
  end
end
