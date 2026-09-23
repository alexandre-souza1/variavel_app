require 'test_helper'

class EmployeeVariableReportTest < ActiveSupport::TestCase
  setup do
    @employee = Employee.create!(nome: 'Pessoa Teste', matricula: 'RH-999')
    %w[ajudante van motorista].each do |cargo|
      { 'valor_caixa' => 1, 'valor_entrega' => 2, 'valor_recarga' => 80 }.each do |name, value|
        CalculationRateVersion.create!(categoria: cargo, nome: name, valor: value)
      end
    end
    CalculationRateVersion.create!(categoria: 'geral', nome: 'bonus_devolucao', valor: 100)
    @employee.change_role!({ cargo: 'ajudante', promax: 'RH-9', starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
  end

  def mapa(day, cargo: 'ajudante', recarga: 'NAO', code: 'RH-9')
    Mapa.create!(mapa: "TEST-#{day}-#{Mapa.count}", data: day, matric_motorista: cargo == 'ajudante' ? 'OUTRO' : code,
      matric_ajudante: cargo == 'ajudante' ? code : nil, fator: 1, cx_real: 10, pdv_real: 5, pdv_total: 5, recarga: recarga)
  end

  test 'promotion uses operation date and preserves helper history with another promax' do
    first = mapa('09/09/2026')
    @employee.change_role!({ cargo: 'van', promax: 'RH-10', starts_on: '2026-09-10', reason: 'Promoção' }, user: users(:one))
    second = mapa('10/09/2026', cargo: 'van', code: 'RH-10', recarga: 'SIM')
    report = EmployeeVariableReport.new(@employee.reload)
    assert_empty report.issues
    assert_equal 'ajudante', report.values(first)[:categoria]
    assert_equal 'van', report.values(second)[:categoria]
    assert_equal 20, report.values(second)[:valor_mp]
    assert_equal 0, report.values(second)[:valor_rec]
    assert report.values(second)[:recarga_inconsistente]
    assert_equal 20, report.totals[:cx_real]
    assert_equal 0, report.totals[:recargas]
    assert_equal Date.new(2026, 9, 9), @employee.employee_roles.order(:starts_on).first.ends_on
    assert_equal 2, @employee.employee_career_events.count
  end

  test 'bonus is separate per role and van recarga counts as a normal map' do
    14.times { mapa('01/09/2026') }
    @employee.change_role!({ cargo: 'van', promax: 'RH-9', starts_on: '2026-09-10', reason: 'Promoção' }, user: users(:one))
    15.times { mapa('11/09/2026', cargo: 'van', recarga: 'SIM') }
    report = EmployeeVariableReport.new(@employee.reload)
    assert_equal 0, report.groups['ajudante'][:bonus_devolucao]
    assert_equal 100, report.groups['van'][:bonus_devolucao]
    assert_equal 100, report.totals[:bonus_devolucao]
    assert_equal 680, report.totals[:valor_total]
  end

  test 'failed or backdated promotion rolls back previous interval and audit' do
    assert_raises(ActiveRecord::RecordInvalid) do
      @employee.change_role!({ cargo: 'invalid', promax: 'RH-9', starts_on: '2026-09-10', reason: 'Teste' }, user: users(:one))
    end
    assert_nil @employee.employee_roles.reload.first.ends_on
    assert_equal 1, @employee.employee_career_events.count
    assert_raises(EmployeeRole::HistoryError) do
      @employee.change_role!({ cargo: 'van', promax: 'RH-9', starts_on: '2025-12-31', reason: 'Teste' }, user: users(:one))
    end
  end

  test 'overlapping intervals are rejected' do
    role = @employee.employee_roles.new(cargo: 'van', promax: 'RH-9', starts_on: '2026-02-01', reason: 'Teste')
    assert_not role.valid?
    assert_includes role.errors.full_messages.join, 'outro cargo'
  end

  test 'rate versions apply by map date and snapshot survives changes with explicit revisions' do
    mapa('01/09/2026')
    CalculationRateVersion.create!(categoria: 'ajudante', nome: 'valor_caixa', valor: 3, effective_on: '2026-09-10')
    mapa('11/09/2026')
    report = EmployeeVariableReport.new(@employee)
    assert_equal 60, report.totals[:valor_total]
    closing = VariableClosing.capture!(employee: @employee, user: users(:one), year: 2026, month: 9, reason: 'Conferido')
    CalculationRateVersion.create!(categoria: 'ajudante', nome: 'valor_caixa', valor: 4, effective_on: '2026-09-10')
    assert_equal 60, closing.reload.result.dig('totals', 'valor_total').to_d
    revision = VariableClosing.capture!(employee: @employee, user: users(:one), year: 2026, month: 9, reason: 'Correção de tarifa')
    assert_equal 2, revision.revision
    assert_equal 70, revision.result.dig('totals', 'valor_total').to_d
    assert_raises(ActiveRecord::ReadOnlyRecord) { closing.update!(reason: 'Sobrescrever') }
  end

  test 'missing history and invalid dates prevent closing' do
    mapa('01/01/2025')
    mapa('inválida')
    report = EmployeeVariableReport.new(@employee)
    assert_equal 2, report.issues.size
    assert_raises(EmployeeRole::HistoryError) { report.validate! }
  end
  test 'same numeric code in the other operational slot does not belong to this employee' do
    unrelated = mapa('01/09/2026', cargo: 'motorista')
    assert_not_includes @employee.maps, unrelated
  end

  test 'role correction adjusts previous boundary and preserves snapshots' do
    mapa('01/09/2026')
    closing = VariableClosing.capture!(employee: @employee, user: users(:one), year: 2026, month: 9, reason: 'Fechado')
    original = closing.result.deep_dup
    role = @employee.change_role!({ cargo: 'van', promax: 'RH-9', starts_on: '2026-09-10', reason: 'Promoção' }, user: users(:one))
    @employee.revise_role!(role.id, { starts_on: '2026-09-12', reason: 'Correção da data' }, user: users(:one))
    assert_equal 'ajudante', @employee.reload.role_on(Date.new(2026, 9, 11)).cargo
    assert_equal 'van', @employee.role_on(Date.new(2026, 9, 12)).cargo
    assert_equal original, closing.reload.result
  end

  test 'van to driver bonuses are not combined' do
    @employee.change_role!({ cargo: 'van', promax: 'RH-9', starts_on: '2026-08-21', reason: 'Promoção' }, user: users(:one))
    10.times { mapa('01/09/2026', cargo: 'van') }
    @employee.change_role!({ cargo: 'motorista', promax: 'RH-9', starts_on: '2026-09-10', reason: 'Promoção' }, user: users(:one))
    10.times { mapa('11/09/2026', cargo: 'motorista') }
    assert_equal 0, EmployeeVariableReport.new(@employee.reload).totals[:bonus_devolucao]
  end

  test 'another person cannot own the same driver code during the same dates' do
    person = Employee.create!(nome: 'Outra Pessoa', matricula: 'RH-OTHER')
    person.change_role!({ cargo: 'motorista', promax: 'RH-9', starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
    assert_raises(ActiveRecord::RecordInvalid) do
      @employee.change_role!({ cargo: 'van', promax: 'RH-9', starts_on: '2026-09-10', reason: 'Promoção' }, user: users(:one))
    end
    assert_equal 'ajudante', @employee.reload.role_on(Date.new(2026, 9, 10)).cargo
  end

end
