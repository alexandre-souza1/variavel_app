require "test_helper"
require "minitest/mock"

class TireScheduleControllerTest < ActionDispatch::IntegrationTest
  setup do
    travel_to Time.zone.local(2026, 10, 27, 12)
    Plate.update_all(active: false)
    @overdue = Plate.create!(placa: "ABC1D23", setor: "ROTA", tipo: "Caminhão", perfil: "TOCO")
    @today = Plate.create!(placa: "DEF4G56", setor: "ROTA", tipo: "Van", perfil: "VAN")
    @missing = Plate.create!(placa: "GHI7J89", setor: "ROTA", tipo: "Caminhão", perfil: "TRUCK")
    Plate.create!(placa: "JKL1M23", setor: "ROTA", tipo: "Caminhão", active: false)
    Plate.create!(placa: "EQUIP01", setor: "ARMAZEM", tipo: "Empilhadeira")
    @records = [inspection(@overdue.placa, "2026-09-01"), inspection(@today.placa, "2026-09-27")]
    records = @records
    @client = Object.new
    @client.define_singleton_method(:tread_inspections) { records }
  end
  teardown { travel_back }

  test "requires authentication" do
    sign_out :user
    get_report tire_schedule_path
    assert_redirected_to new_user_session_path
  end

  test "overview includes all active road vehicles and links to filtered deadlines" do
    Prolog::InspectionsClient.stub :new, @client do
      get_report tire_schedule_path
      assert_response :success
      assert_select "h1", text: /Aferições de pneus/
      assert_select ".tire-view-tabs", count: 0
      assert_select "a.tire-schedule-card", count: 5
      assert_select "a.tire-schedule-card--danger strong", text: "1", count: 2
      assert_select "tbody tr", count: 3
      assert_select "tbody tr:first-child td:first-child a", text: @overdue.placa
      assert_select "td .tire-status--danger", text: "Vencida há 26 dias"
      assert_select "td .tire-status--danger", text: "Vence hoje"
      assert_select "td .tire-status--muted", text: "Sem histórico"
      assert_select "#tire-evolution-chart", count: 0
      assert_select "input[name=start_date]", count: 0
      assert_select "a[href=?]", tire_schedule_path(status: "overdue", q: "", per_page: 50)
      get_report tire_schedule_path, params: { status: "missing" }
      assert_select "tbody tr", count: 1
      assert_select "tbody td:first-child a", text: @missing.placa
      assert_select ".tire-schedule-card--danger strong", text: "1", count: 2
      get_report tire_schedule_path, params: { q: "abc-1d23", status: "overdue" }
      assert_select "tbody tr", count: 1
      assert_select "tbody td:first-child a", text: @overdue.placa
      get_report tire_schedule_path, params: { status: "ok" }
      assert_includes response.body, "Nenhum veículo encontrado"
    end
  end

  test "paginates while keeping all filtered rows in CSV and ignores historical date filters" do
    (1..26).each { |i| Plate.create!(placa: "VAN%04d" % i, setor: "ROTA", tipo: "Van") }
    Prolog::InspectionsClient.stub :new, @client do
      get_report tire_schedule_path, params: { per_page: 25, page: 2, status: "missing", q: "VAN", start_date: "invalid" }
      assert_response :success
      assert_select "tbody tr", count: 1
      assert_select "a[rel=prev]" do |links|
        assert_includes links.first["href"], "status=missing"
        assert_includes links.first["href"], "q=VAN"
        assert_includes links.first["href"], "/pneus/afericoes?"
      end
      get_report tire_schedule_path(format: :csv), params: { per_page: 25, page: 2, status: "missing", q: "VAN" }
      assert_response :success
      assert_equal 27, CSV.parse(response.body.delete_prefix("\uFEFF"), col_sep: ";").size
      get_report tire_schedule_path(format: :csv), params: { status: "today" }
      assert_includes response.body, "27/10/2026"
      assert_includes response.body, "Vence hoje"
      refute_includes response.body, @overdue.placa
    end
  end

  test "integration errors are not shown as missing history or empty results" do
    @client.define_singleton_method(:tread_inspections) { raise Prolog::InspectionsClient::Error, "Falha na consulta" }
    Prolog::InspectionsClient.stub :new, @client do
      get_report tire_schedule_path
      assert_response :service_unavailable
      assert_includes response.body, "Os resultados não foram carregados"
      assert_select ".tire-schedule-cards", count: 0
      refute_includes response.body, "Nenhum veículo encontrado"
    end
  end

  private

  def get_report(path, params: {})
    get path, params: params.merge(load: 1)
  end

  def inspection(plate, date)
    { "id" => 1, "submittedAt" => "#{date}T12:00:00Z", "source" => "vehicles",
      "typeMeasurementsCollected" => "TREAD_DEPTH_PRESSURE", "vehicle" => { "licensePlate" => plate },
      "submittedBy" => { "name" => "Equipe de pneus" } }
  end
end
