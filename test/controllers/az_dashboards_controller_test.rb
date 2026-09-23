require "test_helper"

class AzDashboardsControllerTest < ActionDispatch::IntegrationTest
  test "renders dashboard and filters a cycle crossing years" do
    get dashboard_az_path, params: { mes: 1, ano: 2026 }
    assert_response :success
    assert_select "h1", text: /Dashboard de metas AZ/
    assert_match "19/12/2025", response.body
    assert_match "18/01/2026", response.body
    get dashboard_az_path, params: { mes: 1, ano: 2026, periodo_tipo: "segunda_quinzena", turno: 0 }
    assert_response :success
    assert_match "03/01/2026", response.body
  end

  test "rejects invalid filters and unauthorized users" do
    get dashboard_az_path, params: { mes: 13 }
    assert_redirected_to dashboard_az_path
    get dashboard_az_path, params: { turno: "other" }
    assert_redirected_to dashboard_az_path
    users(:one).update!(role: :user)
    get dashboard_az_path
    assert_redirected_to root_path
  end

  test "calculates turn specific operator targets and includes WMS on final evening" do
    operator = operators(:one)
    operator.update!(turno: 1, active: true)
    ParametroCalculo.where(categoria: "operador").delete_all
    { "valor_tma" => 2, "valor_efc" => 3, "tarefa_wms" => 4 }.each do |name, value|
      ParametroCalculo.create!(categoria: "operador", nome: name, valor: value)
    end
    AzMapa.create!(data: "2026-09-18", tipo: :tempo_atendimento, turno: [0, 1, 2], resultado: 2, atingiu_meta: true)
    AzMapa.create!(data: "2026-09-18", tipo: :eficiencia_descarga, turno: [1], resultado: 95, atingiu_meta: true)
    AzMapa.create!(data: "2026-09-18", tipo: :eficiencia_carregamento, turno: [0, 2], resultado: 100, atingiu_meta: true)
    AzMapa.create!(data: "2026-09-19", tipo: :eficiencia_descarga, turno: [1], resultado: 95, atingiu_meta: true)
    WmsTask.create!(operator: operator, task_code: "dashboard", task_type: "Teste", duration: 60, started_at: Time.zone.parse("2026-09-18 23:00"))
    dashboard = AzDashboardService.new(start_date: Date.new(2026, 8, 19), end_date: Date.new(2026, 9, 18), turno: 1).call
    row = dashboard.operators.find { |item| item[:person].id == operator.id }
    assert_equal 1, row[:tma]
    assert_equal 1, row[:efficiency]
    assert_equal 1, row[:wms]
    assert_equal 9, row[:total]
    assert_equal 0, dashboard.indicators.find { |item| item[:type] == "eficiencia_carregamento" }[:count]
  end

  test "helper amounts use official points refugo and on demand rules" do
    helper = az_ajudantes(:one)
    helper.update!(nome: "José Teste", active: true, turno: 0)
    AzMapa.create!(data: "2026-09-18", tipo: :eficiencia_carregamento, turno: [0, 2], resultado: 95, atingiu_meta: true)
    source = AzRvImport.create!(source_type: "points", original_filename: "test.csv", file_digest: "dashboard-test")
    AzRvPoint.create!(az_rv_import: source, employee_name: helper.nome, employee_key: "jose teste", reference_date: "2026-09-18", total_points: 1000, reported_value: 10)
    AzRvTask.create!(az_rv_import: source, source_key: "dashboard-refugo", employee_name: helper.nome, employee_key: "jose teste", task_type: "Blitz Refugo", associated_at: Time.zone.parse("2026-09-18 23:00"))
    AzRvOnDemandActivity.create!(az_rv_import: source, source_key: "dashboard-demand", employee_name: helper.nome, employee_key: "jose teste", activity: "Maquina de limpeza", created_at_source: Time.zone.parse("2026-09-18 23:00"))
    dashboard = AzDashboardService.new(start_date: Date.new(2026, 8, 19), end_date: Date.new(2026, 9, 18), turno: 0).call
    row = dashboard.helpers.find { |item| item[:person].id == helper.id }
    assert_equal 1000, row[:points]
    assert_equal 10, row[:point_value]
    assert_equal 1, row[:refugo]
    assert_equal 5, row[:activity_value]
    assert_equal BigDecimal("5"), row[:efc_value]
    assert_equal BigDecimal("21.10"), row[:total]
    get dashboard_az_path, params: { mes: 9, ano: 2026, turno: 0 }
    assert_response :success
    assert_select "th", text: "Dias EFC"
    assert_select "th", text: "Valor EFC"
  end
end
