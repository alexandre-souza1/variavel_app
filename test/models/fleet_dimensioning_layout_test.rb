require "test_helper"

class FleetDimensioningLayoutTest < ActiveSupport::TestCase
  setup do
    @dimensioning = FleetDimensioning.create!(
      label: "Teste de movimentação", start_date: Date.new(2090, 1, 1),
      end_date: Date.new(2090, 1, 15), route_quantity: 2,
      van_quantity: 0, vespertina_quantity: 0, as_quantity: 1
    )
    @first = @dimensioning.fleet_dimensioning_standard_plates.create!(plate: plates(:one), position: 0)
    @second = @dimensioning.fleet_dimensioning_standard_plates.create!(plate: plates(:two), position: 1)
  end

  test "requires at least one vehicle" do
    dimensioning = FleetDimensioning.new(
      label: "Dimensionamento sem veículos",
      start_date: Date.new(2091, 1, 1),
      end_date: Date.new(2091, 1, 15),
      route_quantity: 0,
      van_quantity: 0,
      vespertina_quantity: 0,
      as_quantity: 0
    )

    assert_not dimensioning.valid?
    assert_includes dimensioning.errors[:base],
                    "Informe pelo menos um veículo no dimensionamento."
  end

  test "moves a plate directly to an occupied slot" do
    assert @dimensioning.update_configuration(fleet_dimensioning_standard_plates_attributes: {
      "0" => { id: @first.id, plate_id: "", _destroy: "1" },
      "1" => { id: @second.id, plate_id: plates(:one).id, position: 1 }
    })
    assert_equal [[plates(:one).id, 1]], @dimensioning.reload.fleet_dimensioning_standard_plates.pluck(:plate_id, :position)
  end

  test "swaps two assigned plates in one save" do
    assert @dimensioning.update_configuration(fleet_dimensioning_standard_plates_attributes: {
      "0" => { id: @first.id, plate_id: plates(:two).id, position: 0 },
      "1" => { id: @second.id, plate_id: plates(:one).id, position: 1 }
    })
    assert_equal [plates(:two).id, plates(:one).id], @dimensioning.reload.fleet_dimensioning_standard_plates.pluck(:plate_id)
  end

  test "moves to a special route" do
    assert @dimensioning.update_configuration(fleet_dimensioning_standard_plates_attributes: {
      "0" => { id: @first.id, plate_id: "", _destroy: "1" },
      "special_as" => { plate_id: plates(:one).id, special_route: "as" }
    })
    assert_equal "as", @dimensioning.reload.fleet_dimensioning_standard_plates.find_by!(plate_id: plates(:one).id).special_route
  end

  test "invalid changes roll back the original assignments" do
    assert_not @dimensioning.update_configuration(label: "", fleet_dimensioning_standard_plates_attributes: {
      "0" => { id: @first.id, plate_id: "", _destroy: "1" },
      "1" => { id: @second.id, plate_id: plates(:one).id, position: 1 }
    })
    assert_equal [@first.id, @second.id], @dimensioning.reload.fleet_dimensioning_standard_plates.pluck(:id)
  end

  test "rejects duplicate plates in final layout" do
    assert_not @dimensioning.update_configuration(fleet_dimensioning_standard_plates_attributes: {
      "0" => { id: @first.id, plate_id: plates(:two).id, position: 0 }
    })
    assert_includes @dimensioning.errors[:base], "Uma placa não pode ocupar mais de uma posição ou rota especial."
    assert_equal plates(:one).id, @first.reload.plate_id
  end
end
