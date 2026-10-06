require "test_helper"
require "minitest/mock"

class FleetAvailabilityDepartureAlertsTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 7, 20, 9)
    Mapa.delete_all
    @availability = fleet_availabilities(:one)
    FleetAvailability.where(id: @availability.id).update_all([
      "special_routes = ?", { "as" => 1 }.to_json
    ])
    @availability.reload
    @plate = plates(:one)
    @plate.update!(placa: "ABC1D23", setor: "ROTA", tipo: "Caminhão", perfil: "TOCO")
    @item = fleet_availability_items(:one)
    @item.update!(position: 0, reason: nil)
  end

  teardown { travel_back }

  test "shows a discreet departure alert in every board when no monthly map exists" do
    %w[available exchange unavailable special_route].each do |status|
      @item.update!(status: status, special_route: status == "special_route" ? "as" : nil)

      get_availability

      assert_select "#fleet_availability_item_#{@item.id} [data-fleet-departure-alert][tabindex='0']", count: 1 do
        assert_select "[title='Carro sem saída no 2ART'][aria-label='Carro sem saída no 2ART']"
        assert_select ".bi-exclamation-circle[aria-hidden='true']"
      end
    end
  end

  test "matches the stress test green indicators at both month boundaries" do
    second_plate = plates(:two)
    second_plate.update!(placa: "DEF4G56", setor: "ROTA", tipo: "Caminhão", perfil: "TOCO")
    fleet_availability_items(:two).update!(fleet_availability: @availability, reason: nil)
    create_map(data: "1072026")
    create_map(plate: second_plate.placa, data: "31/07/2026")

    get_availability

    assert_select "[data-fleet-departure-alert]", count: 0

    get placas_por_setor_path, params: { mes: 7, ano: 2026 }
    assert_response :success
    assert_select "tbody tr td:nth-child(5) .badge.bg-success", text: /1 dia\(s\)/, count: 2
  end

  test "ignores other months years undated maps and other plates" do
    ["30/06/2026", "01/08/2026", "20/07/2025", nil, "invalid"].each do |date|
      create_map(data: date)
    end
    create_map(plate: "DEF4G56")
    travel_to Time.zone.local(2026, 10, 6, 9)

    get_availability

    assert_select ".fleet-availability-page--readonly"
    assert_select "[data-fleet-departure-alert]", count: 1
  end

  test "recognizes normalized and equivalent old plate numbers from the imported maps" do
    create_map(plate: " abc-1323 ")

    get_availability

    assert_select "[data-fleet-departure-alert]", count: 0
  end

  private

  def create_map(**attributes)
    Mapa.create!({
      mapa: "DEPARTURE-#{Mapa.count}",
      plate: @plate.placa,
      data: @availability.date.strftime("%d/%m/%Y")
    }.merge(attributes))
  end

  def get_availability
    client = Object.new
    client.define_singleton_method(:tread_depth_by_plate) { {} }
    Prolog::TiresClient.stub(:new, client) do
      get fleet_availability_path(@availability)
    end
    assert_response :success
  end
end
