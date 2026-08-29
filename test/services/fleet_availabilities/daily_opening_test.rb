require "test_helper"

class FleetAvailabilities::DailyOpeningTest < ActiveSupport::TestCase
  fixtures :users, :fleet_availabilities

  setup do
    FleetDimensioning.create!(
      label: "Teste diário",
      start_date: Date.new(2026, 7, 1),
      end_date: Date.new(2026, 7, 31),
      route_quantity: 1,
      van_quantity: 0,
      vespertina_quantity: 0,
      as_quantity: 0
    )
  end

  test "does not open a monday availability on saturday" do
    result = FleetAvailabilities::DailyOpening.call(
      user: users(:one),
      now: Time.zone.local(2026, 8, 29, 8, 0)
    )

    assert_equal :sunday, result.skipped_reason
  end

  test "is idempotent when the next day is already open" do
    result = FleetAvailabilities::DailyOpening.call(
      user: users(:one),
      now: Time.zone.local(2026, 7, 20, 8, 0)
    )

    assert_equal Date.new(2026, 7, 21), result.availability.date
    assert_no_difference "FleetAvailability.count" do
      FleetAvailabilities::DailyOpening.call(
        user: users(:one),
        now: Time.zone.local(2026, 7, 20, 8, 0)
      )
    end
  end

  test "locks the next day's availability at the configured time" do
    FleetAvailabilitySetting.current.update!(auto_lock_time: "16:00")

    FleetAvailabilities::DailyOpening.call(
      user: users(:one),
      now: Time.zone.local(2026, 7, 20, 16, 0)
    )

    assert fleet_availabilities(:two).reload.locked?
  end

  test "copies the previous day's layout when opening automatically" do
    previous = fleet_availabilities(:two)
    previous.fleet_availability_items.first.update!(
      status: FleetAvailabilityItem.statuses[:unavailable],
      reason: "maintenance",
      observation: "Copiar integralmente"
    )

    result = FleetAvailabilities::DailyOpening.call(
      user: users(:one),
      now: Time.zone.local(2026, 7, 22, 8, 0)
    )

    copied_item = result.availability.fleet_availability_items.find_by(
      plate_id: previous.fleet_availability_items.first.plate_id
    )

    assert_equal "unavailable", copied_item.status
    assert_equal "maintenance", copied_item.reason
    assert_equal "Copiar integralmente", copied_item.observation
  end
end
