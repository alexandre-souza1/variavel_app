class FleetAvailability::RestoreStandardLayout
  def self.call(fleet_availability)
    new(fleet_availability).call
  end

  def initialize(fleet_availability)
    @fleet_availability = fleet_availability
  end

  def call
    dimensioning = FleetAvailability.dimensioning_period_for(
      @fleet_availability.date
    )

    return unless dimensioning

    standard_positions = dimensioning.standard_plate_by_position

    ActiveRecord::Base.transaction do
      items = @fleet_availability
                .fleet_availability_items
                .includes(:plate)
                .to_a

      items_by_plate = items.index_by(&:plate_id)

      occupied_positions = []
      updates = []

      #
      # Placas padrão
      #
      standard_positions.each do |position, standard|
        item = items_by_plate[standard.plate_id]

        next unless item
        next if item.unavailable?

        occupied_positions << position

        updates << {
          item: item,
          status: :available,
          position: position,
          reason: nil,
          special_route: nil
        }
      end

      #
      # Demais posições livres
      #
      free_positions =
        (0...@fleet_availability.agreed_quantity).to_a -
        occupied_positions

      standard_plate_ids =
        standard_positions
          .values
          .map(&:plate_id)

      remaining_items =
        items.reject do |item|
          item.unavailable? ||
          standard_plate_ids.include?(item.plate_id)
        end

      remaining_items.each do |item|
        if free_positions.any?
          updates << {
            item: item,
            status: :available,
            position: free_positions.shift,
            reason: nil,
            special_route: nil
          }
        else
          updates << {
            item: item,
            status: :exchange,
            position: item.position,
            reason: nil,
            special_route: nil
          }
        end
      end

      #
      # 1ª fase
      # Remove conflitos de posição.
      #
      updates.each_with_index do |update, index|
        update[:item].update_columns(
          position: 10_000 + index
        )
      end

      #
      # 2ª fase
      # Aplica layout definitivo.
      #
      updates.each do |update|
        update[:item].update!(
          status: update[:status],
          position: update[:position],
          reason: update[:reason],
          special_route: update[:special_route]
        )
      end
    end
  end
end
