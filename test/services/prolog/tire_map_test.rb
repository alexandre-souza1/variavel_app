require "test_helper"

class Prolog::TireMapTest < ActiveSupport::TestCase
  test "places dual tires by position independently of tread depth ordering" do
    positions = %w[DD DE D2D D2E TDE TDI TEI TEE TKDE TKDI TKEI TKEE]
    tires = positions.reverse.map { |position| { position: position, fire_number: position } }
    map = Prolog::TireMap.new(Plate.new(perfil: "BITRUCK").tire_layout, tires)

    assert_equal [%w[DD DE], %w[D2D D2E], %w[TDE TDI TEI TEE], %w[TKDE TKDI TKEI TKEE]],
                 map.axles.map { |entry| entry[:tires].map { |tire| tire[:fire_number] } }
    assert_empty map.unmapped_tires
  end

  test "leaves missing positions empty and keeps unrecognized and duplicate positions separate" do
    tires = [{ position: "TDI" }, { position: "120" }, { position: nil }, { position: "TDI" }]
    map = Prolog::TireMap.new(Plate.new(perfil: "TOCO").tire_layout, tires)

    assert_equal [nil, nil], map.axles.first[:tires]
    assert_equal [nil, tires.first, nil, nil], map.axles.last[:tires]
    assert_equal tires.drop(1), map.unmapped_tires
  end

  test "van keeps single rear wheels and spare is excluded from axles" do
    tires = %w[DD DE TD TE].map { |position| { position: position } }
    map = Prolog::TireMap.new(Plate.new(perfil: "VAN").tire_layout, tires + [{ spare: true }])

    assert_equal [%w[DD DE], %w[TD TE]], map.axles.map { |entry| entry[:tires].map { |tire| tire[:position] } }
    assert_empty map.unmapped_tires
  end
end
