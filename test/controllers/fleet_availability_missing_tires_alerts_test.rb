require "test_helper"
require "minitest/mock"

class FleetAvailabilityMissingTiresAlertsTest < ActionDispatch::IntegrationTest
  Response = Struct.new(:code, :parsed_response) do
    def success?
      code.between?(200, 299)
    end
  end

  setup do
    travel_to Time.zone.local(2026, 7, 20, 9)
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

  test "shows a discreet accessible warning in every board and preserves tread depth" do
    %w[available exchange unavailable special_route].each do |status|
      @item.update!(status: status, special_route: status == "special_route" ? "as" : nil)

      get_availability(tires: operational_tires(5))

      message = "Pneus faltantes no Prolog: 5 de 6 pneus em uso cadastrados. Corrija o cadastro no Prolog."
      assert_select "#{card_selector} [data-fleet-missing-tires-alert][data-fleet-card-alert][tabindex='0']", count: 1 do
        assert_select "[title=?][aria-label=?]", message, message
        assert_select ".bi-exclamation-triangle[aria-hidden='true']"
      end
      assert_select "#{card_selector}[data-tread-depth='4.5']"
      assert_select "#{card_selector} .fleet-tread-depth-badge__value", text: /4[,.]5\s*mm/
      assert_equal 1, @requests.size, "O alerta e o sulco devem usar a mesma consulta"
    end
  end

  test "uses each vehicle profile to determine the expected number of operational tires" do
    { "VAN" => 4, "TOCO" => 6, "TRUCK" => 10, "BITRUCK" => 12, "VUC" => 10 }.each do |profile, expected|
      @plate.update!(perfil: profile, tipo: profile == "VAN" ? "Van" : "Caminhão")

      get_availability(tires: operational_tires(expected - 1))

      assert_select "#{card_selector} [data-fleet-missing-tires-alert][title*=?]", "#{expected - 1} de #{expected}"
    end
  end

  test "matches equivalent plates across pages and does not count a spare as an operational tire" do
    tires = operational_tires(5, plate: " abc-1323 ")
    tires << { "smallestTreadDepth" => 1.0, "installed" => { "licensePlate" => @plate.placa, "installedAxle" => 9 } }

    get_availability(tires: tires, page_size: 3)

    assert_select "#{card_selector} [data-fleet-missing-tires-alert][title*='5 de 6']"
    assert_select "#{card_selector}[data-tread-depth='4.5']"
    assert_equal [0, 1], @requests.map { |request| request[:query][:pageNumber] }
  end

  test "does not warn when the tire count is complete even without tread measurements" do
    [6, 7].each do |count|
      get_availability(tires: operational_tires(count, depth: nil))

      assert_select "#{card_selector} [data-fleet-missing-tires-alert]", count: 0
      assert_select "#{card_selector} .fleet-tread-depth-badge", count: 0
    end
  end

  test "warns for vehicles with no registered tires including read only availability" do
    travel_to Time.zone.local(2026, 10, 6, 9)

    get_availability(tires: [])

    assert_select ".fleet-availability-page--readonly"
    assert_select "#{card_selector} [data-fleet-missing-tires-alert][title*='0 de 6']"
    assert_select "#{card_selector} .fleet-tread-depth-badge", count: 0
  end

  test "does not report missing tires when Prolog is unavailable or unconfigured" do
    get_availability(tires: [], response_code: 503)
    assert_select "[data-fleet-missing-tires-alert]", count: 0

    get_availability(tires: [], token: nil)
    assert_select "[data-fleet-missing-tires-alert]", count: 0
    assert_empty @requests
  end

  test "does not warn for unknown profiles or warehouse equipment" do
    @plate.update!(perfil: nil)
    get_availability(tires: [])
    assert_select "[data-fleet-missing-tires-alert]", count: 0

    @plate.update!(setor: "ARMAZEM", tipo: "Empilhadeira", perfil: "GLP")
    get_availability(tires: [])
    assert_select "[data-fleet-missing-tires-alert]", count: 0
  end

  private

  def card_selector
    "#fleet_availability_item_#{@item.id}"
  end

  def operational_tires(count, plate: @plate.placa, depth: 4.5)
    Array.new(count) { { "smallestTreadDepth" => depth, "installed" => { "licensePlate" => plate } } }
  end

  def get_availability(tires:, response_code: 200, token: "test", page_size: 100)
    pages = tires.each_slice(page_size).to_a.presence || [[]]
    @requests = []
    requests = @requests
    http = Object.new
    http.define_singleton_method(:get) do |_url, **options|
      requests << options
      page = options[:query][:pageNumber]
      Response.new(response_code, { "content" => pages.fetch(page), "lastPage" => page == pages.size - 1 })
    end
    client = Prolog::TiresClient.new(token: token, http_client: http)
    Prolog::TiresClient.stub(:new, client) { get fleet_availability_path(@availability) }
    assert_response :success
  end
end
