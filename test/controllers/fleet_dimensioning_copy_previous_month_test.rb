require "test_helper"

class FleetDimensioningCopyPreviousMonthTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2090, 2, 16, 9)
    plates(:one).update!(placa: "ABC1D23", setor: "ROTA", tipo: "Caminhão", perfil: "TOCO")
    plates(:two).update!(placa: "DEF4G56", setor: "ROTA", tipo: "Caminhão", perfil: "TRUCK")
    @special_plate = Plate.create!(placa: "GHI7J89", setor: "ROTA", tipo: "Caminhão", perfil: "VUC")
    @previous = FleetDimensioning.create!(
      label: "Q2 JANEIRO 90", start_date: Date.new(2090, 1, 16), end_date: Date.new(2090, 1, 31),
      route_quantity: 19, van_quantity: 0, vespertina_quantity: 0, as_quantity: 1
    )
    @previous.fleet_dimensioning_standard_plates.create!(plate: plates(:one), position: 0)
    @previous.fleet_dimensioning_standard_plates.create!(plate: plates(:two), position: 18)
    @previous.fleet_dimensioning_standard_plates.create!(plate: @special_plate, special_route: "as")
  end

  teardown { travel_back }

  test "loads the same half of the previous month into an unsaved form" do
    FleetDimensioning.create!(
      label: "Q1 JANEIRO 90", start_date: Date.new(2090, 1, 1), end_date: Date.new(2090, 1, 15),
      route_quantity: 1, van_quantity: 0, vespertina_quantity: 0, as_quantity: 0
    )
    original_assignments = @previous.fleet_dimensioning_standard_plates.map(&:attributes)

    assert_no_difference ["FleetDimensioning.count", "FleetDimensioningStandardPlate.count"] do
      get_previous_layout
    end

    assert_response :success
    assert_select "form[action='#{fleet_dimensionings_path}'][method='post']"
    assert_select "#fleet_dimensioning_period_year option[selected][value='2090']"
    assert_select "#fleet_dimensioning_period_month option[selected][value='2']"
    assert_select "#fleet_dimensioning_period_half option[selected][value='q2']"
    assert_select "#fleet_dimensioning_route_quantity[value='19']"
    assert_select "#fleet_dimensioning_as_quantity[value='1']"
    assert_select "[data-position='0'] [data-fleet-dimensioning-form-target='plateInput'][value='#{plates(:one).id}']"
    assert_select "[data-position='18'] [data-fleet-dimensioning-form-target='plateInput'][value='#{plates(:two).id}']"
    assert_select "[data-special-route='as'] [data-fleet-dimensioning-form-target='plateInput'][value='#{@special_plate.id}']"
    assert_select "input[name$='[id]']", count: 0
    assert_select "[data-fleet-dimensioning-form-target='copyStatus']", text: /Q2 JANEIRO 90/
    assert_equal original_assignments, @previous.reload.fleet_dimensioning_standard_plates.map(&:attributes)
  end

  test "does not copy inactive vehicles" do
    plates(:two).retire!

    get_previous_layout

    assert_response :success
    assert_select "[data-position='18'] [data-fleet-dimensioning-form-target='plateInput']", count: 1 do |inputs|
      assert_equal "", inputs.first["value"].to_s
    end
    assert_select "[data-plate-id='#{plates(:two).id}']", count: 0
  end

  test "the copied form saves a new period with its plate assignments" do
    get_previous_layout
    fields = response.parsed_body.css("form input[name], form select[name]").filter_map do |field|
      next if field["type"] == "submit"

      value = field.name == "select" ? field.at_css("option[selected]")&.[]("value") : field["value"]
      [field["name"], value.to_s]
    end
    query = fields.map { |name, value| "#{Rack::Utils.escape(name)}=#{Rack::Utils.escape(value)}" }.join("&")

    assert_difference "FleetDimensioning.count", 1 do
      post fleet_dimensionings_path, params: Rack::Utils.parse_nested_query(query)
    end

    assert_redirected_to fleet_dimensionings_path
    saved = FleetDimensioning.find_by!(start_date: Date.new(2090, 2, 16))
    assert_equal "Q2 FEVEREIRO 90", saved.label
    assert_equal 19, saved.route_quantity
    columns = %i[plate_id position special_route]
    assert_equal @previous.fleet_dimensioning_standard_plates.reorder(:plate_id).pluck(*columns),
                 saved.fleet_dimensioning_standard_plates.reorder(:plate_id).pluck(*columns)
  end

  test "handles the year change without changing the selected period" do
    @previous.update!(label: "Q2 DEZEMBRO 90", start_date: Date.new(2090, 12, 16), end_date: Date.new(2090, 12, 31))

    get_previous_layout(period_year: 2091, period_month: 1)

    assert_response :success
    assert_select "#fleet_dimensioning_period_year option[selected][value='2091']"
    assert_select "#fleet_dimensioning_period_month option[selected][value='1']"
    assert_select "[data-fleet-dimensioning-form-target='copyStatus']", text: /Q2 DEZEMBRO 90/
  end

  test "reports a missing previous period" do
    get_previous_layout(period_month: 3)

    assert_response :not_found
    assert_match(/Não há dimensionamento/, response.parsed_body["error"])
  end

  test "rejects invalid period selections" do
    get_previous_layout(period_half: "invalid")

    assert_response :unprocessable_entity
    assert_match(/Selecione um ano/, response.parsed_body["error"])
  end

  test "requires authentication" do
    sign_out :user

    get_previous_layout

    assert_redirected_to new_user_session_path
  end

  private

  def get_previous_layout(**period)
    get copy_previous_month_fleet_dimensionings_path,
        params: { fleet_dimensioning: { period_year: 2090, period_month: 2, period_half: "q2" }.merge(period) }
  end
end
