require "test_helper"

class FleetAvailabilityTest < ActiveSupport::TestCase
  test "availability bar is yellow with zero to two spare vehicles green with three and red with a shortage" do
    availability = FleetAvailability.new(date: Date.current, special_routes: {})
    4.times do
      availability.fleet_availability_items.build(plate: plates(:one), status: :exchange)
    end

    { 1 => "bg-success", 2 => "bg-warning", 3 => "bg-warning", 4 => "bg-warning", 5 => "bg-danger" }.each do |required, color|
      availability.agreed_quantity = required
      assert_equal color, availability.operational_availability_bar_class, "Dimensionamento: #{required}"
    end
  end

  test "operational dimensioning is met by enough active vehicles including special route demand" do
    availability = fleet_availabilities(:one)
    availability.agreed_quantity = 1
    availability.special_routes = {}
    fleet_availability_items(:two).update_columns(
      fleet_availability_id: availability.id,
      status: FleetAvailabilityItem.statuses[:unavailable]
    )

    assert_equal 50, availability.operational_percentage
    assert availability.operational_dimensioning_met?

    availability.agreed_quantity = 2
    assert_not availability.operational_dimensioning_met?

    availability.agreed_quantity = 1
    availability.special_routes = { "as" => 1 }
    assert_not availability.operational_dimensioning_met?

    fleet_availability_items(:two).update_columns(status: FleetAvailabilityItem.statuses[:special_route])
    availability.fleet_availability_items.reload
    assert availability.operational_dimensioning_met?

    plates(:one).update_columns(active: false, retired_at: availability.date)
    availability.fleet_availability_items.reload
    assert_not availability.operational_dimensioning_met?
  end

  test "operational percentage includes routing special routes and deposit against total fleet" do
    availability = fleet_availabilities(:one)
    first = fleet_availability_items(:one)
    second = fleet_availability_items(:two)
    second.update_columns(fleet_availability_id: availability.id, status: FleetAvailabilityItem.statuses[:unavailable])

    %w[available exchange special_route].each do |status|
      first.update_columns(status: FleetAvailabilityItem.statuses.fetch(status))
      assert_equal 50, availability.reload.operational_percentage
    end

    second.update_columns(status: FleetAvailabilityItem.statuses[:exchange])
    assert_equal 100, availability.reload.operational_percentage

    first.update_columns(status: FleetAvailabilityItem.statuses[:unavailable])
    second.update_columns(status: FleetAvailabilityItem.statuses[:unavailable])
    assert_equal 0, availability.reload.operational_percentage

    availability.fleet_availability_items.destroy_all
    assert_equal 0, availability.reload.operational_percentage
  end

  test "exchange count excludes inactive plates" do
    availability = fleet_availabilities(:one)
    plate = plates(:one)

    assert_equal 1, availability.exchange_count

    plate.update!(active: false, placa: "ABC1D23", setor: "ROTA", tipo: "Caminhão", perfil: "TOCO")

    assert_equal 0, availability.exchange_count
  end
end
