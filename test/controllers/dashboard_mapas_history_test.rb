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
    assert_equal original, closing.reload.result
  end

  test 'merging snapshots recomputes a weighted percentage per cargo' do
    first = { 'groups' => { 'motorista' => group(real: 95, returned: 5).merge('percentual_devolucao' => '0.05') } }
    second = { 'groups' => { 'motorista' => group(real: 30, returned: 20).merge('percentual_devolucao' => '0.4') } }
    result = VariableClosing.merge_results(first, second, employee: @employee)
    assert_in_delta 25.0 / 150, result['groups']['motorista']['percentual_devolucao'], 0.000001
    assert_equal 246, result['groups']['motorista']['valor_total']
  end
end
