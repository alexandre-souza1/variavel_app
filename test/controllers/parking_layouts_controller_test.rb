require "test_helper"

class ParkingLayoutsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ParkingLayout.delete_all
    Plate.create!(placa: "RTI1I17", tipo: "Van", setor: "ROTA", perfil: "VAN")
    Plate.create!(placa: "QJU2138", tipo: "Caminhão", setor: "ROTA", perfil: "TRUCK")
    @distribution = ParkingLayout.initial_assignments
  end

  test "guest can read the map without editor controls" do
    sign_out users(:one)
    get patio_path
    assert_response :success
    assert_select ".parking-space", count: 40
    assert_select "[data-controller='parking-map']", count: 1
    assert_select ".parking-editor, .parking-drag, [data-action='parking-editor#start']", count: 0
  end

  test "regular user cannot see or invoke editing" do
    users(:one).update!(role: :user)
    get patio_path
    assert_response :success
    assert_select ".parking-editor, .parking-drag", count: 0
    patch patio_path, params: { assignments: @distribution, lock_version: 0 }, as: :json
    assert_response :forbidden
    assert_equal 0, ParkingLayout.count
  end

  test "guest cannot write even with a valid payload" do
    sign_out users(:one)
    patch patio_path, params: { assignments: @distribution, lock_version: 0 }, as: :json
    assert_response :forbidden
    assert_equal 0, ParkingLayout.count
  end

  test "administrator publishes a swap and public sees it" do
    @distribution["1"], @distribution["2"] = @distribution["2"], @distribution["1"]
    patch patio_path, params: { assignments: @distribution, lock_version: 0 }, as: :json
    assert_response :success
    assert_equal @distribution, ParkingLayout.current.assignments
    assert_equal users(:one), ParkingLayout.current.updated_by
    assert_equal 1, ParkingLayout.current.lock_version
    sign_out users(:one)
    get patio_path
    assert_select '.parking-space[data-slot="1"] .parking-vehicle strong', "QJU2138"
    assert_select ".parking-editor", count: 0
  end

  test "duplicate plates and missing positions cannot be saved" do
    @distribution["18"] = @distribution["1"]
    patch patio_path, params: { assignments: @distribution, lock_version: 0 }, as: :json
    assert_response :unprocessable_entity
    assert_equal 0, ParkingLayout.count
    patch patio_path, params: { assignments: { "1" => "RTI1I17" }, lock_version: 0 }, as: :json
    assert_response :unprocessable_entity
    assert_equal 0, ParkingLayout.count
  end

  test "unregistered plates are rejected" do
    @distribution["18"] = "ZZZ0Z00"
    patch patio_path, params: { assignments: @distribution, lock_version: 0 }, as: :json
    assert_response :unprocessable_entity
    assert_equal 0, ParkingLayout.count
  end

  test "new registered active vehicle can be assigned" do
    Plate.create!(placa: "XYZ1A23", tipo: "Caminhão", setor: "ROTA", perfil: "TOCO")
    @distribution["18"] = "XYZ1A23"
    patch patio_path, params: { assignments: @distribution, lock_version: 0 }, as: :json
    assert_response :success
    assert_equal "XYZ1A23", ParkingLayout.current.assignments["18"]
  end

  test "stale publication does not overwrite another administrator" do
    patch patio_path, params: { assignments: @distribution, lock_version: 0 }, as: :json
    assert_response :success
    @distribution["1"] = ""
    patch patio_path, params: { assignments: @distribution, lock_version: 0 }, as: :json
    assert_response :conflict
    assert_equal "RTI1I17", ParkingLayout.current.assignments["1"]
  end

  test "missing version and malformed data are rejected" do
    patch patio_path, params: { assignments: @distribution }, as: :json
    assert_response :unprocessable_entity
    patch patio_path, params: { assignments: [], lock_version: 0 }, as: :json
    assert_response :unprocessable_entity
    assert_equal 0, ParkingLayout.count
  end
  test "retired plates disappear from both map and editor and cannot be assigned" do
    patch patio_path, params: { assignments: @distribution, lock_version: 0 }, as: :json
    assert_response :success
    Plate.find_by!(placa: "RTI1I17").retire!
    get patio_path
    assert_response :success
    assert_select '[data-plate="RTI1I17"]', count: 0
    assert_select 'option[value="RTI1I17"]', count: 0
    patch patio_path, params: { assignments: @distribution, lock_version: 1 }, as: :json
    assert_response :unprocessable_entity
    sign_out users(:one)
    get patio_path
    assert_select '[data-plate="RTI1I17"]', count: 0
  end

  test "plates from PDF absent in active registry are not offered" do
    get patio_path
    assert_select 'option[value="GHK2F66"]', count: 0
    assert_select '[data-plate="GHK2F66"]', count: 0
  end

end
