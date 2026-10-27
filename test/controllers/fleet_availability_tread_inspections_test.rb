require "test_helper"
require "minitest/mock"

class FleetAvailabilityTreadInspectionsTest < ActionDispatch::IntegrationTest
  setup do
    @availability = fleet_availabilities(:one)
    @plate = plates(:one)
  end

  test "returns the latest tread inspection date in the application time zone" do
    inspected_at = Time.iso8601("2026-10-20T01:30:00Z")
    client = Minitest::Mock.new
    client.expect(:last_tread_inspection_at, inspected_at, [@plate.placa])

    Time.use_zone("America/Sao_Paulo") do
      Prolog::InspectionsClient.stub(:new, client) { get_inspection }
    end

    assert_response :success
    assert_equal "Última aferição de sulcos do veículo: 19/10/2026 às 22:30.", response.parsed_body["message"]
    assert_equal inspected_at.iso8601, response.parsed_body["inspected_at"]
    client.verify
  end

  test "returns a clear message when there is no tread inspection" do
    client = Struct.new(:last_tread_inspection_at) do
      def last_tread_inspection_at(_plate) = nil
    end.new
    Prolog::InspectionsClient.stub(:new, client) { get_inspection }

    assert_response :success
    assert_nil response.parsed_body["inspected_at"]
    assert_match "não encontrada no Prolog", response.parsed_body["message"]
  end

  test "reports integration failures without inventing a date" do
    client = Object.new
    client.define_singleton_method(:last_tread_inspection_at) { |_plate| raise Prolog::InspectionsClient::Error, "unavailable" }
    Prolog::InspectionsClient.stub(:new, client) { get_inspection }

    assert_response :service_unavailable
    assert_match "Não foi possível consultar", response.parsed_body["message"]
    assert_nil response.parsed_body["inspected_at"]
  end

  test "rejects plates outside this availability before querying Prolog" do
    Prolog::InspectionsClient.stub(:new, -> { flunk "Unexpected Prolog request" }) do
      get tread_inspection_fleet_availability_path(@availability, plate_id: plates(:two).id), as: :json
    end
    assert_response :not_found
  end

  test "requires authentication" do
    sign_out users(:one)
    Prolog::InspectionsClient.stub(:new, -> { flunk "Unexpected Prolog request" }) { get_inspection }
    assert_response :unauthorized
  end

  test "renders focusable hover tooltips without loading inspection history on page open" do
    client = Struct.new(:tire_summary_by_plate, :error).new({
      PlateUtils.normalizar(@plate.placa) => { minimum_tread_depth: 4.5, operational_count: 6 }
    }, nil)

    Prolog::InspectionsClient.stub(:new, -> { flunk "Inspection history must load on hover" }) do
      Prolog::TiresClient.stub(:new, client) { get fleet_availability_path(@availability) }
    end

    assert_response :success
    assert_select ".fleet-tread-depth-badge[data-controller='tread-inspection'][tabindex='0']", count: 1 do
      assert_select "[data-tread-inspection-url-value=?]", tread_inspection_fleet_availability_path(@availability, plate_id: @plate.id)
      assert_select "[data-action*='mouseenter->tread-inspection#load'][data-action*='focus->tread-inspection#load']"
    end
  end

  private

  def get_inspection
    get tread_inspection_fleet_availability_path(@availability, plate_id: @plate.id), as: :json
  end
end
