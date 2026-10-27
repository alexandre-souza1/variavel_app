require "test_helper"
require "minitest/mock"

class FleetAvailabilityVanExceptionsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 7, 20, 7)
    @availability = fleet_availabilities(:one)
    FleetAvailability.where(id: @availability.id).update_all(["special_routes = ?", { van: 1, as: 1 }.to_json])
    @availability.reload
    @item = fleet_availability_items(:one)
    @item.update!(position: 0, reason: nil)
    @item.plate.update!(placa: "ABC1D23", setor: "ROTA", tipo: "Caminhão", perfil: "TOCO")
  end

  teardown { travel_back }

  test "a non van plate requires explicit confirmation and rejected changes leave no history" do
    [nil, false, "false", "0"].each do |confirmation|
      assert_no_difference "FleetAvailabilityChange.count" do
        move_item(confirm_non_van_plate: confirmation)
      end
      assert_response :unprocessable_entity
      assert_predicate @item.reload, :exchange?
      assert_nil @item.special_route
    end
  end

  test "confirmation allows the exception and records the move" do
    assert_difference "FleetAvailabilityChange.count", 1 do
      move_item(confirm_non_van_plate: true)
    end
    assert_response :success
    assert_predicate @item.reload, :special_route?
    assert_equal "van", @item.special_route
    assert_equal "TOCO", response.parsed_body.fetch("plate_profile")
    assert_equal "special_route", @item.fleet_availability_changes.last.to_status
  end

  test "van plates keep working without confirmation" do
    @item.plate.update!(tipo: "Van", perfil: "VAN")
    move_item
    assert_response :success
    assert_equal "van", @item.reload.special_route
  end

  test "a confirmed exception supports later edits but reentry requires a new confirmation" do
    move_item(confirm_non_van_plate: true)
    assert_response :success

    move_item(observation: "Uso excepcional nesta operação")
    assert_response :success
    assert_equal "Uso excepcional nesta operação", @item.reload.observation

    move_item(status: "exchange", special_route: nil)
    assert_response :success
    move_item
    assert_response :unprocessable_entity
    assert_predicate @item.reload, :exchange?
  end

  test "confirmation does not bypass the dimensioned quota" do
    other = @availability.fleet_availability_items.create!(plate: plates(:two), status: :exchange, position: 1)
    other.update!(status: :special_route, special_route: "van", confirm_non_van_plate: true)

    move_item(confirm_non_van_plate: true)
    assert_response :unprocessable_entity
    assert_predicate @item.reload, :exchange?
  end

  test "confirmation does not enable an undimensioned route" do
    FleetAvailability.where(id: @availability.id).update_all(["special_routes = ?", {}.to_json])
    move_item(confirm_non_van_plate: true)
    assert_response :unprocessable_entity
    assert_predicate @item.reload, :exchange?
  end

  test "confirmation does not bypass read only access" do
    @availability.lock_availability!(users(:one))
    move_item(confirm_non_van_plate: true)
    assert_response :forbidden
    assert_predicate @item.reload, :exchange?
  end

  test "other special routes do not require van confirmation" do
    move_item(special_route: "as")
    assert_response :success
    assert_equal "as", @item.reload.special_route
  end

  test "truck in a van slot has a distinct profile exception instead of a changed plate warning" do
    set_standard_van
    move_item(confirm_non_van_plate: true)
    assert_response :success

    get_availability

    assert_select "#fleet_availability_item_#{@item.id}.fleet-plate-item--van-exception" do
      assert_select "[data-van-profile-exception]", text: "Exceção de perfil na Van"
      assert_select ".fleet-plate-card__changed-badge", count: 0
      assert_select "[data-live-details]", text: /Placa padrão:\s+DEF4G56/
    end
    assert_select "#fleet_availability_item_#{@item.id}.fleet-plate-item--changed", count: 0

    @availability.lock_availability!(users(:one))
    get_availability
    assert_select "#fleet_availability_item_#{@item.id} [data-van-profile-exception]", count: 1
  end

  test "a different van keeps the ordinary changed plate warning" do
    set_standard_van
    @item.plate.update!(tipo: "Van", perfil: "VAN")
    move_item
    assert_response :success

    get_availability

    assert_select "#fleet_availability_item_#{@item.id}.fleet-plate-item--changed" do
      assert_select ".fleet-plate-card__changed-badge", text: "Placa diferente"
      assert_select "[data-van-profile-exception]", count: 0
    end
    assert_select "#fleet_availability_item_#{@item.id}.fleet-plate-item--van-exception", count: 0
  end

  private

  def set_standard_van
    plates(:two).update!(placa: "DEF4G56", setor: "ROTA", tipo: "Van", perfil: "VAN")
    dimensioning = FleetDimensioning.create!(label: "Van padrão", start_date: @availability.date.beginning_of_month,
      end_date: @availability.date.end_of_month, route_quantity: 1, van_quantity: 1, as_quantity: 1, vespertina_quantity: 0)
    dimensioning.fleet_dimensioning_standard_plates.create!(plate: plates(:two), special_route: "van")
  end

  def get_availability
    client = Struct.new(:tire_summary_by_plate, :error).new({}, nil)
    Prolog::TiresClient.stub(:new, client) { get fleet_availability_path(@availability) }
    assert_response :success
  end

  def move_item(**attributes)
    patch fleet_availability_fleet_availability_item_path(@availability, @item),
          params: { fleet_availability_item: { status: "special_route", special_route: "van", position: 0 }.merge(attributes) },
          as: :json
  end
end
