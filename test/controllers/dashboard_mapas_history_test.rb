require 'test_helper'

class DashboardMapasHistoryTest < ActionDispatch::IntegrationTest
  setup do
    @employee = Employee.create!(nome: 'Pessoa Fechamento Consolidado', matricula: 'DASH-MERGE')
    @employee.change_role!({ cargo: 'motorista', promax: 'DASH-MERGE', starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
  end

  def group(real:, returned:)
    { 'pdv_real' => real, 'devolucoes' => returned, 'cx_real' => 30, 'recargas' => 0,
      'quantidade_mapas' => 2, 'total_mapas' => 2, 'bonus_devolucao' => 0,
      'valor_total' => 123, 'valor_caixas' => 100, 'valor_pdvs' => 23, 'valor_recargas' => 0 }
  end

  test 'dashboard renders previously merged driver and helper groups without percentage' do
    result = { 'groups' => { 'motorista' => group(real: 95, returned: 5), 'ajudante' => group(real: 80, returned: 20) }, 'maps' => [] }
    closing = VariableClosing.create!(employee: @employee, user: users(:one), year: 2026, month: 9, revision: 1, reason: 'Legado mesclado', result: result)
    original = closing.result.deep_dup
    get dashboard_mapas_path, params: { mes: 9, ano: 2026 }
    assert_response :success
    assert_select 'td', text: '5.0%'
    assert_select 'td', text: '20.0%'
    assert_select '.mapas-ranking-name', text: @employee.nome, count: 2
    assert_select '.mapas-ranking-name', text: /\((MOTORISTA|AJUDANTE)\)/i, count: 0
    assert_equal original, closing.reload.result
  end

  test 'merging snapshots recomputes a weighted percentage per cargo' do
    first = { 'groups' => { 'motorista' => group(real: 95, returned: 5).merge('percentual_devolucao' => '0.05') } }
    second = { 'groups' => { 'motorista' => group(real: 30, returned: 20).merge('percentual_devolucao' => '0.4') } }
    result = VariableClosing.merge_results(first, second, employee: @employee)
    assert_in_delta 25.0 / 150, result['groups']['motorista']['percentual_devolucao'], 0.000001
    assert_equal 246, result['groups']['motorista']['valor_total']
  end

  test 'chart carousels show the ten highest and lowest values independently of map counts' do
    names = []
    12.times do |index|
      person = index.zero? ? @employee : Employee.create!(nome: "Pessoa do gráfico #{index}", matricula: "DASH-CHART-#{index}")
      cargo = index == 11 ? 'van' : 'motorista'
      person.change_role!({ sector: 'du', cargo: cargo, promax: "DASH-CHART-#{index}", starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one)) unless index.zero?
      names << (cargo == 'van' ? "#{person.nome} · Van" : person.nome)
      totals = group(real: 95, returned: 5).merge('valor_total' => index, 'quantidade_mapas' => 12 - index)
      helpers = totals.merge('valor_total' => 100 + index)
      VariableClosing.create!(employee: person, user: users(:one), year: 2026, month: 9, revision: 1, reason: 'Fechamento', result: { 'groups' => { cargo => totals, 'ajudante' => helpers }, 'maps' => [] })
    end

    get dashboard_mapas_path, params: { mes: 9, ano: 2026 }
    assert_response :success
    carousels = css_select('#mapas-productivity-page [data-controller="chart-carousel"]')
    assert_equal 2, carousels.size
    driver_slides = JSON.parse(carousels.first['data-chart-carousel-slides-value'])
    helper_slides = JSON.parse(carousels.last['data-chart-carousel-slides-value'])
    assert_equal names.reverse.first(10), driver_slides.first['data'].map(&:first)
    assert_equal names.first(10), driver_slides.last['data'].map(&:first)
    assert_equal (102..111).to_a.reverse, helper_slides.first['data'].map { |entry| entry.last.to_i }
    assert_equal (100..109).to_a, helper_slides.last['data'].map { |entry| entry.last.to_i }
    assert_select '.mapas-chart-dot[aria-pressed="true"]', count: 3
    assert_select '.mapas-ranking-table tbody tr:first-child .mapas-ranking-name', text: @employee.nome, count: 2
    assert_select '#mapas-devolution-title', count: 0
    assert_select '#mapas-productivity-page .mapas-chart-card', count: 3
    assert_select '#mapas-devolution-page[hidden] .mapas-chart-card', count: 3
    assert_select '#mapas-team-details', count: 0
    assert_select '.mapas-devolution-ranking .mapas-chart-toggle', count: 2
    assert_select '#mapas-variable-average-page[hidden] .mapas-chart-card', count: 3
    assert_select '[data-chart-pages-target="dot"]', count: 3
    assert_select '.mapas-variable-comparison .mapas-chart-toggle', count: 4
  end

  test 'management PDF includes immutable closing amounts and exports the requested fortnight' do
    closing = VariableClosing.create!(employee: @employee, user: users(:one), year: 2026, month: 9,
      revision: 1, reason: 'Fechamento', result: { groups: { motorista: group(real: 95, returned: 5) }, maps: [] })
    original = closing.result.deep_dup
    get dashboard_mapas_path(format: :pdf), params: { mes: 9, ano: 2026 }
    assert_response :success
    assert_equal 'application/pdf', response.media_type
    assert response.body.start_with?('%PDF-')
    assert_equal original, closing.reload.result
    get dashboard_mapas_path(format: :pdf), params: { mes: 9, ano: 2026, periodo_tipo: 'primeira_quinzena' }
    assert_response :success
    assert_match '2026-08-21-2026-09-04.pdf', response.headers['Content-Disposition']
  end

  test 'management PDF uses the dashboard access policy' do
    sign_out users(:one)
    get dashboard_mapas_path(format: :pdf)
    assert_response :unauthorized
    sign_in users(:one)
    users(:one).update!(role: :user, sector: :warehouse)
    get dashboard_mapas_path(format: :pdf)
    assert_response :forbidden
  end
end
