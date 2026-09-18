require "test_helper"

class PlateTest < ActiveSupport::TestCase
  test "retiring a plate preserves the record and marks the retirement date" do
    plate = Plate.create!(placa: "TEST-RETIRE-1", setor: "ARMAZEM", tipo: "Empilhadeira", perfil: "GLP")

    plate.retire!

    assert_not plate.reload.active?
    assert_equal Date.current, plate.retired_at
    assert_includes Plate.inactive, plate
  end

  test "reactivating a plate clears the retirement date" do
    plate = Plate.create!(placa: "TEST-RETIRE-2", setor: "ARMAZEM", tipo: "Empilhadeira", perfil: "GLP")
    plate.retire!

    plate.reactivate!

    assert_predicate plate.reload, :active?
    assert_nil plate.retired_at
  end

  test "returns the expected tire map for each truck profile" do
    expected_counts = { "VUC" => 6, "TOCO" => 4, "TRUCK" => 6, "BITRUCK" => 8, "VAN" => 4 }

    expected_counts.each do |profile, installed_tires|
      plate = Plate.new(perfil: profile)

      assert_equal installed_tires, plate.tire_layout.sum { |axle| axle[:tires] }
      assert_equal installed_tires / 2, plate.tire_layout.size
      assert_equal 2, plate.tire_layout.first[:tires]
    end
  end
end
