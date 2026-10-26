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

  test "opens monday on saturday without creating a sunday availability" do
    assert_difference "FleetAvailability.count", 1 do
      result = FleetAvailabilities::DailyOpening.call(
        user: users(:one),
        now: Time.zone.local(2026, 7, 25, 8, 0)
      )

      assert_nil result.skipped_reason
      assert_equal Date.new(2026, 7, 27), result.availability.date
    end

    assert_not FleetAvailability.exists?(date: Date.new(2026, 7, 26))
  end

  test "does not open monday before the configured opening time on saturday" do
    FleetAvailabilitySetting.current.update!(auto_open_time: "09:00")

    assert_no_difference "FleetAvailability.count" do
      result = FleetAvailabilities::DailyOpening.call(
        user: users(:one),
        now: Time.zone.local(2026, 7, 25, 8, 0)
      )

      assert_equal :before_opening, result.skipped_reason
    end
  end

  test "reuses monday availability on repeated saturday and sunday executions" do
    result = FleetAvailabilities::DailyOpening.call(
      user: users(:one),
      now: Time.zone.local(2026, 7, 25, 8, 0)
    )

    assert_no_difference "FleetAvailability.count" do
      [Time.zone.local(2026, 7, 25, 9, 0), Time.zone.local(2026, 7, 26, 8, 0)].each do |now|
        repeated = FleetAvailabilities::DailyOpening.call(user: users(:one), now: now)

        assert_equal result.availability.id, repeated.availability.id
      end
    end
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

  test "fills empty positions from the deposit before automatic closing" do
    FleetAvailabilitySetting.current.update!(auto_lock_time: "16:00")
    item = fleet_availability_items(:one)

    FleetAvailabilities::DailyOpening.call(
      user: users(:one),
      now: Time.zone.local(2026, 7, 20, 16, 0)
    )

    item.reload
    assert item.available?
    assert_equal 0, item.position
    assert_includes item.observation, "Movimentação automática no fechamento"
    assert_equal 1, FleetAvailabilityChange.where(
      fleet_availability_item: item,
      from_status: :exchange,
      to_status: :available
    ).count
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

  test "keeps a truck in the van slot across consecutive automatic openings" do
    FleetDimensioning.find_by!(label: "Teste diário").update!(van_quantity: 1)
    previous = fleet_availabilities(:two)
    FleetAvailability.where(id: previous.id).update_all(["special_routes = ?", { van: 1 }.to_json])
    previous.reload
    item = previous.fleet_availability_items.first
    item.plate.update!(placa: "DOV1A23", setor: "ROTA", tipo: "Caminhão", perfil: "TOCO")
    item.update!(status: :special_route, special_route: "van", confirm_non_van_plate: true,
                 observation: "Caminhão substituindo a Van")

    [22, 23].each do |day|
      result = nil
      assert_difference "FleetAvailability.count", 1 do
        result = FleetAvailabilities::DailyOpening.call(
          user: users(:one), now: Time.zone.local(2026, 7, day, 8, 0)
        )
      end

      assert_nil result.skipped_reason
      assert_equal Date.new(2026, 7, day + 1), result.availability.date
      copy = result.availability.fleet_availability_items.find_by!(plate_id: item.plate_id)
      assert_equal "van", copy.special_route
      assert_equal item.position, copy.position
      assert_predicate copy, :van_profile_exception?
      assert_not copy.confirm_non_van_plate
      assert_predicate copy, :valid?
      assert_equal "Caminhão substituindo a Van", copy.observation
      copy.update!(observation: "Caminhão substituindo a Van")
    end
  end
end
