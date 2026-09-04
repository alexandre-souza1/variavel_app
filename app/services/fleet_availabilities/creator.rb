module FleetAvailabilities
  class Creator
    def self.call(...)
      new(...).call
    end

    def initialize(
      user:,
      date:,
      agreed_quantity:,
      special_routes: [],
      copy_from: nil,
      copy_previous_day: false
    )
      @user = user
      @date = date.to_date
      @agreed_quantity = agreed_quantity.to_i
      @special_routes = special_routes
      @copy_from = copy_from
      @copy_previous_day = copy_previous_day
    end

    def call
      ActiveRecord::Base.transaction do
        availability = create_availability

        if @copy_from.present?
          copy_all_items(availability, @copy_from)
        elsif @copy_previous_day
          copy_previous_day_items(availability)
        else
          create_items_from_previous_day(availability)
        end

        availability
      end
    end

    private

    def create_availability
      FleetAvailability.create!(
        user: @user,
        date: @date,
        agreed_quantity: @agreed_quantity,
        special_routes: @special_routes
      )
    end

    def base_item_attributes(availability_id)
      {
        fleet_availability_id: availability_id,
        reason: nil,
        observation: nil,
        special_route: nil,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    def copy_previous_day_items(availability)
      previous = previous_day_availability

      if previous
        copy_all_items(availability, previous)
      else
        create_default_items(availability)
      end
    end

    def create_default_items(availability)
      base = base_item_attributes(availability.id)

      items = Plate.active
                   .where(setor: "ROTA")
                   .ordered
                   .each_with_index
                   .map do |plate, index|

        status =
          if index < availability.agreed_quantity.to_i
            FleetAvailabilityItem.statuses[:available]
          else
            FleetAvailabilityItem.statuses[:exchange]
          end

        base.merge(
          plate_id: plate.id,
          status: status,
          position: index
        )
      end

      FleetAvailabilityItem.insert_all!(items) if items.any?
    end

    def copy_all_items(availability, source)
      items = source.fleet_availability_items.map do |item|
        {
          fleet_availability_id: availability.id,
          plate_id: item.plate_id,
          status: FleetAvailabilityItem.statuses.fetch(item.status),
          position: item.position,
          reason: item.reason,
          observation: item.observation,
          special_route: item.special_route,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      FleetAvailabilityItem.insert_all!(items) if items.any?
    end

    # Mantido para os fluxos que não fazem uma cópia integral.
    def create_items_from_previous_day(availability)
      previous = previous_day_availability

      if previous
        create_items_with_unavailable_from_previous(availability, previous)
      else
        create_default_items(availability)
      end
    end

    def create_items_with_unavailable_from_previous(availability, previous)
      base = base_item_attributes(availability.id)
      total_positions = availability.agreed_quantity.to_i

      all_plates = Plate.active
                        .where(setor: "ROTA")
                        .ordered
                        .to_a

      unavailable_items = previous.fleet_availability_items
                                   .where(
                                     status: FleetAvailabilityItem.statuses[:unavailable]
                                   )
                                   .order(:position)

      unavailable_by_position = {}
      extra_unavailable = []

      unavailable_items.each do |item|
        data = {
          plate_id: item.plate_id,
          status: FleetAvailabilityItem.statuses[:unavailable],
          position: item.position,
          reason: item.reason,
          observation: item.observation,
          special_route: item.special_route
        }

        if item.position < total_positions
          unavailable_by_position[item.position] = data
        else
          extra_unavailable << data
        end
      end

      items = []
      occupied_positions = Set.new

      unavailable_by_position.each do |position, data|
        items << base.merge(
          plate_id: data[:plate_id],
          status: data[:status],
          position: position,
          reason: data[:reason],
          observation: data[:observation],
          special_route: data[:special_route]
        )

        occupied_positions.add(position)
      end

      used_plate_ids = items.filter_map { |item| item[:plate_id] }

      available_plates = all_plates.reject do |plate|
        used_plate_ids.include?(plate.id)
      end

      position = 0

      available_plates.each do |plate|
        position += 1 while occupied_positions.include?(position)

        break if position >= total_positions

        items << base.merge(
          plate_id: plate.id,
          status: FleetAvailabilityItem.statuses[:available],
          position: position
        )

        occupied_positions.add(position)
        position += 1
      end

      extra_unavailable.each_with_index do |data, index|
        position = total_positions + index

        items << base.merge(
          plate_id: data[:plate_id],
          status: data[:status],
          position: position,
          reason: data[:reason],
          observation: data[:observation],
          special_route: data[:special_route]
        )
      end

      used_plate_ids = items.filter_map { |item| item[:plate_id] }

      remaining_plates = all_plates.reject do |plate|
        used_plate_ids.include?(plate.id)
      end

      remaining_plates.each_with_index do |plate, index|
        position =
          total_positions +
          extra_unavailable.size +
          index

        items << base.merge(
          plate_id: plate.id,
          status: FleetAvailabilityItem.statuses[:exchange],
          position: position
        )
      end

      FleetAvailabilityItem.insert_all!(items) if items.any?
    end

    def previous_day_availability
      FleetAvailability
        .where("date < ?", @date)
        .order(date: :desc)
        .first
    end
  end
end
