class FleetAvailability::RestoreStandardLayout
  class Error < StandardError; end

  def self.call(fleet_availability)
    new(fleet_availability).call
  end

  def initialize(fleet_availability)
    @fleet_availability = fleet_availability
  end

  def call
    dimensioning = FleetAvailability.dimensioning_period_for(@fleet_availability.date)
    raise Error, "Não há dimensionamento cadastrado para esta data." unless dimensioning

    @fleet_availability.with_lock do
      @fleet_availability.sync_dimensioning!
      items = @fleet_availability.fleet_availability_items.includes(:plate).to_a
      movable_items = items.reject(&:unavailable?)
      items_by_plate = movable_items.index_by(&:plate_id)
      free_positions = (0...@fleet_availability.agreed_quantity).to_a
      assignments = {}

      dimensioning.standard_plate_by_position.each do |position, standard|
        item = items_by_plate[standard.plate_id]
        next unless item && free_positions.include?(position)

        assignments[item] = { status: :available, position: position, special_route: nil }
        free_positions.delete(position)
      end

      dimensioning.standard_plate_by_special_route.each do |route, standard|
        item = items_by_plate[standard.plate_id]
        next unless item && @fleet_availability.special_route_quantity(route).positive?

        assignments[item] = { status: :special_route, position: item.position, special_route: route }
      end

      # Keep existing special-route vehicles in slots without an available default.
      @fleet_availability.special_routes.each do |route, quantity|
        used = assignments.values.count { |assignment| assignment[:special_route] == route }
        movable_items.select { |item| item.special_route? && item.special_route == route }.each do |item|
          next if assignments.key?(item) || used >= quantity

          assignments[item] = { status: :special_route, position: item.position, special_route: route }
          used += 1
        end
      end

      movable_items.each do |item|
        next if assignments.key?(item)

        position = free_positions.shift
        assignments[item] = {
          status: position.nil? ? :exchange : :available,
          position: position || item.position,
          special_route: nil
        }
      end

      # Release both occupied positions and route quotas before applying swaps.
      movable_items.each do |item|
        item.update_columns(status: FleetAvailabilityItem.statuses[:exchange], special_route: nil)
      end
      assignments.each do |item, attributes|
        item.update!(attributes.merge(reason: nil))
      end
    end
  end
end
