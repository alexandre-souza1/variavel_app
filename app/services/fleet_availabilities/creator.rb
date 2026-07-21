module FleetAvailabilities
  class Creator
    def self.call(...)
      new(...).call
    end

    def initialize(user:, date:, agreed_quantity:, special_routes: [], copy_from: nil)
      @user = user
      @date = date
      @agreed_quantity = agreed_quantity
      @special_routes = special_routes
      @copy_from = copy_from
    end

    def call
      ActiveRecord::Base.transaction do
        availability = create_availability

        @copy_from.present? ? copy_items(availability) : create_default_items(availability)

        availability
      end
    end

    def create_availability
      FleetAvailability.create!(
        user: @user,
        date: @date,
        agreed_quantity: @agreed_quantity,
        special_routes: @special_routes
      )
    end

    private

    def create_default_items(availability)
      items = Plate.where(setor: "ROTA")
             .ordered
             .each_with_index.map do |plate, index|
        status =
          if index < availability.agreed_quantity
            FleetAvailabilityItem.statuses[:available]
          else
            FleetAvailabilityItem.statuses[:exchange]
          end

        {
          fleet_availability_id: availability.id,
          plate_id: plate.id,
          status: status,
          position: index,
          created_at: Time.current,
          updated_at: Time.current
        }
      end

      FleetAvailabilityItem.insert_all!(items)
    end

    def copy_items(availability)
      # Implementaremos na Sprint 3
    end
  end
end
