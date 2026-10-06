require "test_helper"

class FleetAvailabilityRestoreStandardLayoutTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2090, 4, 6, 7)
    @availability = fleet_availabilities(:one)
    FleetAvailability.where(id: @availability.id).update_all([
      "date = ?, agreed_quantity = ?, special_routes = ?, locked_at = NULL",
      Date.new(2090, 4, 7), 2, { van: 1, vespertina: 1, as: 1 }.to_json
    ])
    @availability.reload
    plates(:one).update!(placa: "ABC1D23", setor: "ROTA", tipo: "Caminhão", perfil: "TOCO")
    plates(:two).update!(placa: "DEF4G56", setor: "ROTA", tipo: "Caminhão", perfil: "TOCO")
    @first = fleet_availability_items(:one)
    @first.update!(status: :exchange, position: 0, reason: nil)
    @second = add_item(plates(:two), 1)
    @van = add_item(new_plate("GHI7J89", van: true), 2)
    @vespertina = add_item(new_plate("JKL1M23"), 3)
    @as = add_item(new_plate("NOP4Q56"), 4)
    @spare = add_item(new_plate("RST7U89", van: true), 5)
    @dimensioning = FleetDimensioning.create!(
      label: "Q1 ABRIL 90", start_date: Date.new(2090, 4, 1), end_date: Date.new(2090, 4, 15),
      route_quantity: 2, van_quantity: 1, vespertina_quantity: 1, as_quantity: 1
    )
    @dimensioning.fleet_dimensioning_standard_plates.create!(plate: @first.plate, position: 0)
    @dimensioning.fleet_dimensioning_standard_plates.create!(plate: @second.plate, position: 1)
    { "van" => @van, "vespertina" => @vespertina, "as" => @as }.each do |route, item|
      @dimensioning.fleet_dimensioning_standard_plates.create!(plate: item.plate, special_route: route)
    end
  end

  teardown { travel_back }

  test "button restores normal positions and all three special route defaults" do
    restore

    assert_response :success
    assert_equal({ 0 => @first.plate_id, 1 => @second.plate_id }, @dimensioning.standard_plate_by_position.transform_values(&:plate_id))
    assert_layout @first, "available", 0
    assert_layout @second, "available", 1
    assert_special @van, "van"
    assert_special @vespertina, "vespertina"
    assert_special @as, "as"
    assert_predicate @spare.reload, :exchange?
  end

  test "restores swapped positions and replaces occupied special routes without quota conflicts" do
    @first.update!(status: :available, position: 1)
    @second.update!(status: :available, position: 0)
    @spare.update!(status: :special_route, special_route: "van")
    @vespertina.update!(status: :special_route, special_route: "as")
    @as.update!(status: :special_route, special_route: "vespertina")

    restore

    assert_response :success
    assert_layout @first, "available", 0
    assert_layout @second, "available", 1
    assert_special @van, "van"
    assert_special @vespertina, "vespertina"
    assert_special @as, "as"
    assert_predicate @spare.reload, :exchange?
    assert_nil @spare.special_route
  end

  test "keeps unavailable plates and their reasons and retains a special route substitute" do
    @first.update!(status: :unavailable, reason: :maintenance, observation: "Na oficina")
    @van.update!(status: :unavailable, reason: :breakdown, observation: "Aguardando reparo")
    @spare.update!(status: :special_route, special_route: "van")
    substitute = add_item(new_plate("VWX1Y23"), 6)
    unchanged = [@first.attributes, @van.attributes]

    restore

    assert_response :success
    assert_equal unchanged, [@first.reload.attributes, @van.reload.attributes]
    assert_layout substitute, "available", 0
    assert_layout @second, "available", 1
    assert_special @spare, "van"
  end

  test "uses updated dimensioning quantities and ignores positions and routes no longer active" do
    @dimensioning.update!(route_quantity: 1, van_quantity: 0, vespertina_quantity: 0, as_quantity: 0)
    @second.update!(status: :available, position: 1)
    @van.update!(status: :special_route, special_route: "van")

    restore

    assert_response :success
    assert_equal 1, @availability.reload.agreed_quantity
    assert_empty @availability.special_routes
    assert_layout @first, "available", 0
    [@second, @van, @vespertina, @as, @spare].each do |item|
      assert_predicate item.reload, :exchange?
      assert_nil item.special_route
    end
  end

  test "supports a dimensioning with only special routes" do
    @dimensioning.update!(route_quantity: 0)

    restore

    assert_response :success
    assert_equal 0, @availability.reload.agreed_quantity
    assert_equal 0, @availability.available_count
    assert_special @van, "van"
    assert_special @vespertina, "vespertina"
    assert_special @as, "as"
  end

  test "reports missing dimensioning without changing plates" do
    @dimensioning.destroy!
    before = @availability.fleet_availability_items.map(&:attributes)

    restore

    assert_response :unprocessable_entity
    assert_equal "Não há dimensionamento cadastrado para esta data.", response.parsed_body.fetch("error")
    assert_equal before, @availability.fleet_availability_items.reload.map(&:attributes)
  end

  test "locked availability rejects the adjustment as JSON without redirecting" do
    FleetAvailability.where(id: @availability.id).update_all(["locked_at = ?", Time.current])
    before = @availability.fleet_availability_items.map(&:attributes)

    restore

    assert_response :forbidden
    assert_match "travada", response.parsed_body.fetch("error")
    assert_equal before, @availability.fleet_availability_items.reload.map(&:attributes)
  end

  test "invalid default reports its validation and rolls back all moves and quantity changes" do
    @van.plate.update!(tipo: "Caminhão", perfil: "TOCO")
    @dimensioning.update!(route_quantity: 1)
    @first.update!(status: :available, position: 1)
    before = @availability.fleet_availability_items.map(&:attributes)

    restore

    assert_response :unprocessable_entity
    assert_match "precisa ser VAN", response.parsed_body.fetch("error")
    assert_equal before, @availability.fleet_availability_items.reload.map(&:attributes)
    assert_equal 2, @availability.reload.agreed_quantity
  end

  private

  def restore
    patch restore_standard_layout_fleet_availability_path(@availability), as: :json
  end

  def new_plate(placa, van: false)
    Plate.create!(placa: placa, setor: "ROTA", tipo: van ? "Van" : "Caminhão", perfil: van ? "VAN" : "TOCO")
  end

  def add_item(plate, position)
    @availability.fleet_availability_items.create!(plate: plate, position: position, status: :exchange)
  end

  def assert_layout(item, status, position)
    item.reload
    assert_equal status, item.status
    assert_equal position, item.position
    assert_nil item.special_route
  end

  def assert_special(item, route)
    item.reload
    assert_predicate item, :special_route?
    assert_equal route, item.special_route
    assert_not_nil item.position
  end
end
