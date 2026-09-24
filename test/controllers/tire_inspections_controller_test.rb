require "test_helper"
require "minitest/mock"

class TireInspectionsControllerTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.zone.local(2026, 9, 24, 12) }
  teardown { travel_back }
  test "requires authentication" do
    sign_out :user
    get tire_inspections_path
    assert_redirected_to new_user_session_path
  end

  test "renders and exports all severity classifications" do
    records = [inspection(1, "2026-06-01", 4), inspection(2, "2026-07-01", 4.5), inspection(3, "2026-08-01", 5.01), inspection(4, "2026-09-01", 7.02)]
    client = Object.new
    client.define_singleton_method(:fetch) { |**options| records }
    Prolog::InspectionsClient.stub :new, client do
      get tire_inspections_path, params: { start_date: "2026-06-24", end_date: "2026-09-24" }
      assert_response :success
      assert_select "td span.badge", text: "Divergência baixa", count: 1
      assert_select "td span.badge", text: "Divergência média", count: 1
      assert_select "td span.tire-status--success", text: "Divergência baixa", count: 1
      assert_select "td span.tire-status--warning", text: "Divergência média", count: 1
      assert_select "td span.tire-status--danger", text: "Divergência alta", count: 1
      get tire_inspections_path(format: :csv), params: { start_date: "2026-06-24", end_date: "2026-09-24", status: "medium" }
      assert_response :success
      assert_includes response.body, "0,51"
      assert_includes response.body, "Divergência média"
      refute_includes response.body, "Divergência baixa"
    end
  end

  test "invalid dates do not query prolog" do
    get tire_inspections_path, params: { start_date: "invalid" }
    assert_response :unprocessable_entity
    assert_includes response.body, "Informe um período válido"
  end

  test "API errors are not presented as no divergences" do
    client = Object.new
    client.define_singleton_method(:fetch) { |**options| raise Prolog::InspectionsClient::Error, "Falha na consulta" }
    Prolog::InspectionsClient.stub :new, client do
      get tire_inspections_path
      assert_response :service_unavailable
      assert_includes response.body, "Os resultados não foram carregados"
      refute_includes response.body, "Nenhum aumento de sulco"
    end
  end

  test "paginates html but exports all filtered divergences" do
    records = (1..61).map do |id|
      item = inspection(id, "2026-07-01", 4 + id * 0.01)
      item["submittedAt"] = (Time.utc(2026, 7, 1) + id.hours).iso8601
      item
    end
    client = Object.new
    client.define_singleton_method(:fetch) { |**options| records }
    Prolog::InspectionsClient.stub :new, client do
      get tire_inspections_path, params: { start_date: "2026-06-24", end_date: "2026-09-24", q: "PNEU", page: 1 }
      assert_response :success
      assert_select "tbody tr", count: 50
      assert_select "#tire-evolution-chart"
      assert_select "#tire-distribution-chart"
      chart_script = response.parsed_body.css("script").map(&:text).find { |text| text.include?("tire-evolution-chart") }
      get tire_inspections_path, params: { start_date: "2026-06-24", end_date: "2026-09-24", q: "PNEU", per_page: 25, page: 2 }
      assert_select "tbody tr", count: 25
      assert_select "select[name=per_page] option[selected]", text: "25"
      assert_select "a[aria-current=page]", text: "2"
      assert_equal chart_script, response.parsed_body.css("script").map(&:text).find { |text| text.include?("tire-evolution-chart") }
      assert_select "a[rel=next]" do |links|
        assert_includes links.first["href"], "q=PNEU"
      end
      assert_select "#fleetDropdown", text: /FROTA/
      assert_select "#mobileFleetCollapse a", text: "Pneus"
      get tire_inspections_path, params: { start_date: "2026-06-24", end_date: "2026-09-24", page: 2 }
      assert_select "tbody tr", count: 10
      get tire_inspections_path, params: { start_date: "2026-06-24", end_date: "2026-09-24", per_page: 100, page: 999 }
      assert_select "tbody tr", count: 60
      assert_select "a[aria-current=page]", text: "1"
      get tire_inspections_path, params: { start_date: "2026-06-24", end_date: "2026-09-24", per_page: -1 }
      assert_select "tbody tr", count: 50
      get tire_inspections_path(format: :csv), params: { start_date: "2026-06-24", end_date: "2026-09-24", per_page: 25, page: 2 }
      assert_equal 61, CSV.parse(response.body.delete_prefix("\uFEFF"), col_sep: ";").size
    end
  end

  test "pressure view filters persistence and exports pressure followup" do
    records = [inspection(1, "2026-07-01", 4), inspection(2, "2026-08-01", 4)]
    records.each { |r| r["inspectionMeasures"].first.merge!("measuredPressure" => 80, "recommendedPressure" => 100) }
    client = Object.new
    client.define_singleton_method(:fetch) { |**options| records }
    Prolog::InspectionsClient.stub :new, client do
      get tire_inspections_path, params: { view: "pressure", status: "persisted" }
      assert_response :success
      assert_select "tbody tr", count: 1
      assert_select "td span.badge", text: "Permaneceu baixa"
      get tire_inspections_path, params: { view: "pressure", status: "awaiting_month" }
      assert_response :success
      assert_select "tbody tr", count: 1
      assert_select "td span.tire-status--warning", text: "Pressão baixa · sem aferição no mês atual"
      get tire_inspections_path(format: :csv), params: { view: "pressure" }
      assert_response :success
      assert_includes response.body, "Pressão seguinte"
      assert_includes response.body, "Pressão baixa · sem aferição no mês atual"
    end
  end

  test "orders by measured depth before pagination and preserves order in CSV" do
    records = (1..31).flat_map do |id|
      [inspection(id * 2, "2026-07-01", id), inspection(id * 2 + 1, "2026-08-01", id + 0.5)].each do |record|
        record["inspectionMeasures"].first.merge!("tireId" => id, "tireSerialNumber" => "PNEU-#{id}")
      end
    end
    client = Object.new
    client.define_singleton_method(:fetch) { |**options| records }
    Prolog::InspectionsClient.stub :new, client do
      get tire_inspections_path, params: { sort: "depth_asc", per_page: 25, page: 2 }
      assert_response :success
      assert_select "tbody tr:first-child td:first-child strong", text: "PNEU-26"
      assert_select "input[name=sort][value=depth_asc]"
      assert_select "a[rel=prev]" do |links|
        assert_includes links.first["href"], "sort=depth_asc"
      end
      get tire_inspections_path(format: :csv), params: { sort: "depth_asc", per_page: 25, page: 2 }
      data = CSV.parse(response.body.delete_prefix("\uFEFF"), col_sep: ";")
      assert_equal 32, data.size
      assert_equal "PNEU-1", data[1][0]
      assert_equal "PNEU-31", data.last[0]
      get tire_inspections_path, params: { sort: "depth_desc" }
      assert_select "tbody tr:first-child td:first-child strong", text: "PNEU-31"
    end
  end

  test "defaults to newest inspection including invalid sort values" do
    records = [inspection(1, "2026-07-01", 1), inspection(2, "2026-08-01", 4), inspection(3, "2026-09-01", 4.1)]
    client = Object.new
    client.define_singleton_method(:fetch) { |**options| records }
    Prolog::InspectionsClient.stub :new, client do
      [nil, "invalid"].each do |sort|
        get tire_inspections_path, params: { sort: sort }
        assert_response :success
        assert_select "select[name=sort] option[selected]", text: "Aferições mais recentes"
        assert_select "tbody tr:first-child td:nth-child(4)", text: /01\/09\/2026/
      end
    end
  end

  private

  def inspection(id, date, depth)
    { "id" => id, "source" => "vehicles", "submittedAt" => "#{date}T12:00:00Z", "inspectionMeasures" => [
      { "tireId" => 1, "tireSerialNumber" => "PNEU-1", "tireLifeCycleAtInspection" => 1, "measuredInnerTreadDepth" => depth }
    ] }
  end
end
