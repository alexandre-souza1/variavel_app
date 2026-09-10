module FleetAvailabilities
  class AutoCloser
    OBSERVATION_PREFIX = "Movimentação automática no fechamento".freeze

    Result = Data.define(:locked_count, :moved_count)

    def self.call(user:, now: Time.current)
      new(user: user, now: now).call
    end

    def initialize(user:, now:)
      @user = user
      @now = now.in_time_zone
    end

    def call
      return Result.new(0, 0) unless FleetAvailability.locking_enabled?
      return legacy_lock_result unless @user

      moved_count = 0
      locked_count = 0

      eligible_availabilities.find_each do |availability|
        moved_count += fill_empty_positions!(availability)
        availability.lock_availability!(@user)
        deliver(availability)
        locked_count += 1
      end

      Result.new(locked_count, moved_count)
    end

    private

    def eligible_availabilities
      setting = FleetAvailabilitySetting.current
      today = @now.to_date
      scope = FleetAvailability.where(locked_at: nil, auto_lock_exempted_at: nil)
                              .where("date < ?", today)

      if setting.auto_lock_at(today) <= @now
        scope = scope.or(
          FleetAvailability.where(
            locked_at: nil,
            auto_lock_exempted_at: nil,
            date: today..(today + 1.day)
          )
        )
      end

      scope
    end

    def legacy_lock_result
      Result.new(FleetAvailability.auto_lock_expired!(now: @now), 0)
    end

    def fill_empty_positions!(availability)
      items = availability.fleet_availability_items.includes(:plate).to_a
      target_positions = (0...availability.agreed_quantity.to_i).to_a
      occupied_positions = items.filter_map do |item|
        item.position if target_positions.include?(item.position)
      end
      empty_positions = target_positions - occupied_positions
      exchange_items = items.select(&:exchange?).sort_by { |item| [item.position, item.id] }
      moved_items = exchange_items.first(empty_positions.size)

      moved_items.each_with_index do |item, index|
        position = empty_positions[index]
        observation = [
          OBSERVATION_PREFIX,
          "placa #{item.plate.placa} do depósito para a posição #{position + 1}."
        ].join(": ")

        item.update_columns(position: 10_000 + item.id, updated_at: Time.current)
        item.update!(
          status: :available,
          position: position,
          reason: nil,
          special_route: nil,
          observation: observation
        )
        FleetAvailabilityChange.create!(
          fleet_availability_item: item,
          user: @user,
          from_status: :exchange,
          to_status: :available,
          observation: observation
        )
      end

      moved_items.size
    end

    def deliver(availability)
      NotificationDelivery.fleet_availability_sent(
        fleet_availability: availability,
        actor: @user
      )

      setting = FleetAvailabilityEmailSetting.current
      return unless setting.deliverable?

      FleetAvailabilityMailer
        .locked_availability(availability, @user)
        .deliver_now
    rescue StandardError => e
      Rails.logger.error(
        "Falha ao enviar disponibilidade automática #{availability.id}: " \
        "#{e.class} - #{e.message}"
      )
    end
  end
end
