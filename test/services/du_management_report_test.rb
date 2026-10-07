require 'test_helper'

class DuManagementReportTest < ActiveSupport::TestCase
  test 'exports every carousel variant and reports partial periods, incomplete history and inconsistent data' do
    valid = Mapa.new(data: '10/09/2026', matric_motorista: 'UNKNOWN-D', matric_ajudante: 'UNKNOWN-H', pdv_total: 100, pdv_real: 90, recarga: 'NAO')
    invalid = Mapa.new(data: '10/09/2026', pdv_total: 0, pdv_real: nil, recarga: 'NAO')
    row = { person_key: 'driver-test', nome: 'Pessoa com variável zerada', matricula: 'MGT-1', mapas: 1, valor_total: 0, source: 'calculated' }
    averages = DuVariableAverageReport.new(driver_ranking: [row], helper_ranking: [], year: 2026, month: 9)
    report = DuManagementReport.new(maps: [valid, invalid], drivers: [row], helpers: [],
      devolution: DuDevolutionReport.new([valid, invalid]), averages: averages,
      from: Date.new(2026, 8, 21), to: Date.new(2026, 9, 4), partial: true, issues: ['Promax sem vigência.'])
    assert_equal 14, report.charts.size
    assert_equal 0, report.total_variable
    alerts = report.alerts.map(&:first)
    assert_includes alerts, 'Período parcial'
    assert_includes alerts, 'Devolução geral acima de 3%'
    assert_includes alerts, 'PDVs inconsistentes'
    assert_includes alerts, 'Vínculo de colaborador'
    assert_includes alerts, 'Colaborador sem identificação segura'
    assert_includes alerts, 'Variável zerada'
    assert_includes alerts, 'Histórico de motoristas'
    assert DuManagementPdf.new(report).render.start_with?('%PDF-')
  end
end
