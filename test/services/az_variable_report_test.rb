require 'test_helper'

class AzVariableReportTest < ActiveSupport::TestCase
  setup do
    AzMapa.delete_all
    @from, @to = Date.new(2026, 8, 19), Date.new(2026, 9, 18)
    %w[valor_tma valor_efc tarefa_wms].each do |name|
      rate = ParametroCalculo.find_or_initialize_by(categoria: 'operador', nome: name)
      rate.update!(valor: 2)
    end
    @person = Employees::Registry.create!(attributes: { nome: 'Operador unificado', matricula: 'AZ-REPORT', data_nascimento: '1990-01-01' },
      role: { sector: 'az', cargo: 'operador', turno: 0, starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
  end

  def report = AzVariableReport.for_period(person: @person, from: @from, to: @to)

  test 'all AZ consumers include the evening of the last closing day and exclude the next day' do
    operator = @person.operators.first
    [Time.zone.local(2026, 9, 18, 23, 59), Time.zone.local(2026, 9, 19)].each_with_index do |date, index|
      WmsTask.create!(operator: operator, task_code: "EDGE-#{index}", task_type: 'Tarefa', duration: 10, started_at: date)
    end
    assert_equal 2, report.component(:wms)
    row = AzDashboardService.new(start_date: @from, end_date: @to).call.operators.find { |entry| entry[:person].employee_id == @person.id }
    assert_equal report.total, row[:total]
    context = PublicVariableContext.new(PublicVariableIdentity.new('colaborador', @person)).call
    assert_equal report.total.to_f, context.dig(:data, :monthly, '2026-09', :total)
  end

  test 'dated shift changes select the correct efficiency on each operation date' do
    @person.change_role!({ sector: 'az', cargo: 'operador', turno: 1, starts_on: '2026-09-10', reason: 'Troca de turno' }, user: users(:one))
    ['2026-09-09', '2026-09-10'].each do |date|
      AzMapa.create!(data: date, tipo: :eficiencia_carregamento, turno: [0, 2], resultado: 95, atingiu_meta: true)
      AzMapa.create!(data: date, tipo: :eficiencia_descarga, turno: [1], resultado: 95, atingiu_meta: true)
    end
    assert_equal 4, report.component(:efficiency)
    assert_equal 0, report.daily.find { |day| day[:date] == Date.new(2026, 9, 9) }[:turno]
    assert_equal 1, report.daily.find { |day| day[:date] == Date.new(2026, 9, 10) }[:turno]
    row_a = AzDashboardService.new(start_date: @from, end_date: @to, turno: 0).call.operators.find { |row| row[:person].employee_id == @person.id }
    row_b = AzDashboardService.new(start_date: @from, end_date: @to, turno: 1).call.operators.find { |row| row[:person].employee_id == @person.id }
    assert_equal 2, row_a[:efficiency_value]
    assert_equal 2, row_b[:efficiency_value]
  end

  test 'helper shift components and shared EFC respect transfer dates' do
    @person.change_role!({ sector: 'az', cargo: 'ajudante', turno: 0, starts_on: '2026-09-01', reason: 'Mudança de função' }, user: users(:one))
    @person.change_role!({ sector: 'az', cargo: 'ajudante', turno: 1, starts_on: '2026-09-10', reason: 'Troca de turno' }, user: users(:one))
    ['2026-08-20', '2026-09-09', '2026-09-10'].each do |date|
      AzMapa.create!(data: date, tipo: :eficiencia_carregamento, turno: [0, 2], resultado: 95, atingiu_meta: true)
      AzMapa.create!(data: date, tipo: :suprimento, turno: [0], resultado: 95, atingiu_meta: true)
      AzMapa.create!(data: date, tipo: :remonte, turno: [1], resultado: 100, atingiu_meta: true)
    end
    assert_equal 10, report.component(:efc)
    assert_equal 4, report.component(:suprimento)
    assert_equal 10, report.component(:remonte)
  end

  test 'recorded AZ closing preserves roles rates sources and amounts after corrections' do
    AzMapa.create!(data: '2026-09-10', tipo: :eficiencia_carregamento, turno: [0, 2], resultado: 95, atingiu_meta: true)
    closing = VariableClosing.capture!(employee: @person, user: users(:one), year: 2026, month: 9, sector: 'az', reason: 'Conferido')
    ParametroCalculo.find_by!(categoria: 'operador', nome: 'valor_efc').update!(valor: 999)
    @person.revise_role!(@person.employee_roles.first.id, { sector: 'az', cargo: 'operador', turno: 1, starts_on: '2026-01-01', reason: 'Correção de turno' }, user: users(:one))
    assert_equal 2, report.total
    assert_equal 0, report.role_on(Date.new(2026, 9, 10)).turno
    assert_equal 2, report.map_value(report.maps.first)
    assert_equal 'az', closing.sector
    assert_equal 1, closing.revision
    revised = VariableClosing.capture!(employee: @person, user: users(:one), year: 2026, month: 9, sector: 'az', reason: 'Nova revisão')
    assert_equal 2, revised.revision
    assert_equal 2, closing.reload.result['total'].to_d
  end

  test 'renaming a helper preserves stable imported activity ownership' do
    @person.change_role!({ sector: 'az', cargo: 'ajudante', turno: 0, starts_on: '2026-08-01', reason: 'Função' }, user: users(:one))
    source = AzRvImport.create!(source_type: 'ondemand', original_filename: 'identity.csv', file_digest: 'identity-unified')
    activity = AzRvOnDemandActivity.create!(az_rv_import: source, source_key: 'identity-unified', employee_name: @person.nome,
      employee_key: EmployeeName.normalize(@person.nome), activity: 'Maquina de limpeza', created_at_source: Time.zone.local(2026, 9, 10))
    assert_equal @person.id, activity.employee_id
    Employees::Registry.update!(@person, attributes: { nome: 'Nome corrigido' }, user: users(:one), reason: 'Correção')
    assert_equal 5, report.component(:ondemand)
    assert_equal @person.id, EmployeeName.resolve('Operador unificado').id
  end

  test 'saved source details use the recorded rates for helper points and activities' do
    @person.change_role!({ sector: 'az', cargo: 'ajudante', turno: 0, starts_on: '2026-08-01', reason: 'Função' }, user: users(:one))
    source = AzRvImport.create!(source_type: 'ondemand', original_filename: 'snapshot.csv', file_digest: 'detail-snapshot')
    AzRvPoint.create!(az_rv_import: source, employee_name: @person.nome,
      employee_key: EmployeeName.normalize(@person.nome), reference_date: '2026-09-10', total_points: 1000)
    AzRvOnDemandActivity.create!(az_rv_import: source, source_key: 'snapshot-activity', employee_name: @person.nome,
      employee_key: EmployeeName.normalize(@person.nome), activity: 'Maquina de limpeza', created_at_source: Time.zone.local(2026, 9, 10))
    VariableClosing.capture!(employee: @person, user: users(:one), year: 2026, month: 9, sector: 'az', reason: 'Conferência de fontes')
    recorded = report
    recorded.points.first.define_singleton_method(:montagem_value) { BigDecimal('999') }
    recorded.activities.first.define_singleton_method(:rv_amount) { BigDecimal('999') }
    assert_equal recorded.component(:point_value), recorded.point_value(recorded.points.first)
    assert_equal recorded.component(:ondemand), recorded.activity_value(recorded.activities.first)
  end
end
