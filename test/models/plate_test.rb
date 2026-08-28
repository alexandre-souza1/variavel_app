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
end
