require "test_helper"

class FleetDimensioningSpecialRoutesTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2090, 4, 6, 9)
    plates(:one).update!(placa: "ABC1D23", setor: "ROTA", tipo: "Van", perfil: "VAN")
    plates(:two).update!(placa: "DEF4G56", setor: "ROTA", tipo: "Caminhão", perfil: "TRUCK")
    @third_plate = Plate.create!(placa: "GHI7J89", setor: "ROTA", tipo: "Caminhão", perfil: "VUC")
  end

  teardown { travel_back }

  test "new form has all special route slots ready for quantity changes" do
    get new_fleet_dimensioning_path

    assert_response :success
    assert_select "[data-fleet-dimensioning-form-target='specialRoutes'].d-none"
    FleetAvailability::SPECIAL_ROUTES.each_key do |route|
      assert_select "[data-route-key='#{route}'].d-none"
      assert_select "[data-special-route='#{route}'] [data-fleet-dimensioning-form-target='slotList']"
      assert_select "#fleet_dimensioning_#{route}_quantity[data-action='input->fleet-dimensioning-form#syncSlots'][data-special-route-quantity='#{route}']"
    end
  end

  test "new form saves special route plates when the initial quantities were zero" do
    get new_fleet_dimensioning_path
    parameters = form_parameters
    attributes = parameters.fetch("fleet_dimensioning")
    { "van" => plates(:one), "vespertina" => plates(:two), "as" => @third_plate }.each do |route, plate|
      attributes["#{route}_quantity"] = "1"
      attributes.fetch("fleet_dimensioning_standard_plates_attributes").fetch("special_#{route}").merge!(
        "plate_id" => plate.id.to_s, "_destroy" => "0"
      )
    end

    assert_difference "FleetDimensioning.count", 1 do
      assert_difference "FleetDimensioningStandardPlate.count", 3 do
        post fleet_dimensionings_path, params: parameters
      end
    end

    assert_redirected_to fleet_dimensionings_path
    saved = FleetDimensioning.find_by!(start_date: Date.new(2090, 4, 1))
    assert_equal({ "vespertina" => 1, "van" => 1, "as" => 1 }, saved.special_routes)
    assert_equal ["as", "van", "vespertina"], saved.fleet_dimensioning_standard_plates.pluck(:special_route).sort
  end

  test "zeroing a special route removes its saved plate assignment" do
    dimensioning = FleetDimensioning.create!(
      label: "Q1 ABRIL 90", start_date: Date.new(2090, 4, 1), end_date: Date.new(2090, 4, 15),
      route_quantity: 1, van_quantity: 0, vespertina_quantity: 0, as_quantity: 1
    )
    dimensioning.fleet_dimensioning_standard_plates.create!(plate: @third_plate, special_route: "as")
    get edit_fleet_dimensioning_path(dimensioning)
    parameters = form_parameters
    attributes = parameters.fetch("fleet_dimensioning")
    attributes["as_quantity"] = "0"
    attributes.fetch("fleet_dimensioning_standard_plates_attributes").fetch("special_as").merge!(
      "plate_id" => "", "_destroy" => "1"
    )

    assert_difference "FleetDimensioningStandardPlate.count", -1 do
      patch fleet_dimensioning_path(dimensioning), params: parameters
    end

    assert_redirected_to fleet_dimensionings_path
    assert_empty dimensioning.reload.special_routes
    assert_empty dimensioning.fleet_dimensioning_standard_plates
  end

  private

  def form_parameters
    fields = response.parsed_body.css("form input[name], form select[name]").filter_map do |field|
      next if field["type"] == "submit"

      value = field.name == "select" ? field.at_css("option[selected]")&.[]("value") : field["value"]
      [field["name"], value.to_s]
    end
    query = fields.map { |name, value| "#{Rack::Utils.escape(name)}=#{Rack::Utils.escape(value)}" }.join("&")
    Rack::Utils.parse_nested_query(query)
  end
end
