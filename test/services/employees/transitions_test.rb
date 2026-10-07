require 'test_helper'

class EmployeesTransitionsTest < ActiveSupport::TestCase
  setup do
    @person = Employees::Registry.create!(attributes: { nome: 'Pessoa em transferência', matricula: 'TRANS-100', data_nascimento: '1990-01-01' },
      role: { sector: 'du', cargo: 'motorista', promax: 'TRANS-PROMAX', starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
    @date = Date.new(2026, 10, 2)
  end

  test 'a DU to AZ transfer removes operational eligibility on its effective day and separates closing revisions' do
    schedule = TimeOffSchedule.create!(name: 'Transição', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28')
    member = TimeOff::AssignGroup.call(schedule: schedule, person: @person, group_code: 'A', starts_on: @date, user: users(:one))
    @person.change_role!({ sector: 'az', cargo: 'operador', turno: 1, starts_on: '2026-10-10', reason: 'Transferência' }, user: users(:one))
    member.reload
    assert member.active_person?(Date.new(2026, 10, 9))
    refute member.active_person?(Date.new(2026, 10, 10))
    assert Pcd::Board.new(date: Date.new(2026, 10, 9)).member("employee:#{@person.id}")
    assert_nil Pcd::Board.new(date: Date.new(2026, 10, 10)).member("employee:#{@person.id}")
    du = VariableClosing.capture!(employee: @person, user: users(:one), year: 2026, month: 10, sector: 'du', reason: 'DU conferida')
    az = VariableClosing.capture!(employee: @person, user: users(:one), year: 2026, month: 10, sector: 'az', reason: 'AZ conferida')
    assert_equal 1, du.revision
    assert_equal 1, az.revision
    assert du.result['roles'].all? { |role| role['sector'] == 'du' }
    assert_equal '2026-09-19', az.result['from']
    assert AzVariableReport.for_period(person: @person, from: Date.new(2026, 9, 19), to: Date.new(2026, 10, 18)).daily.all? { |day| day[:date] >= Date.new(2026, 10, 10) }
  end

  test 'changing a Promax retains the previous operational code on earlier dates' do
    @person.change_role!({ cargo: 'motorista', promax: 'NEW-PROMAX', starts_on: '2026-10-10', reason: 'Correção com vigência' }, user: users(:one))
    assert_equal 'TRANS-PROMAX', Pcd::Board.new(date: @date).member("employee:#{@person.id}")['code']
    assert_equal 'NEW-PROMAX', Pcd::Board.new(date: Date.new(2026, 10, 10)).member("employee:#{@person.id}")['code']
  end

  test 'the upgrade provisions missing legacy RH adapters without replacing existing operational identities' do
    require Rails.root.join('db/migrate/20261007120000_backfill_employee_operational_links')
    Driver.where(employee_id: @person.id).delete_all
    existing_id = drivers(:one).id
    migration = BackfillEmployeeOperationalLinks.new
    migration.suppress_messages { migration.up }
    adapter = @person.drivers.reload.first
    assert_equal @person.id, adapter.employee_id
    assert_equal 'TRANS-PROMAX', adapter.promax
    assert Driver.exists?(existing_id)
    assert_no_difference('Driver.count') { migration.suppress_messages { migration.up } }
    schedule = TimeOffSchedule.create!(name: 'RH legado', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28')
    member = TimeOff::AssignGroup.call(schedule: schedule, person: @person, group_code: 'A', starts_on: @date, user: users(:one))
    assert_equal @person.id, member.employee_id
  end

  test 'consumption follows registration aliases and excludes operations outside driver DU history' do
    @person.change_role!({ sector: 'az', cargo: 'operador', turno: 1, starts_on: '2026-10-10', reason: 'Transferência' }, user: users(:one))
    Employees::Registry.update!(@person, attributes: { matricula: 'TRANS-200' }, user: users(:one), reason: 'Matrícula corrigida')
    [9, 10].each do |day|
      GasolaSupply.create!(external_id: "TRANS-SUPPLY-#{day}", registration: 'TRANS-100', concluded_at: Time.zone.local(2026, 10, day, 12),
        status: 'CONCLUDED', category: 'veículo', fuel: 'dieselS10', liters: 100, distance: 400)
    end
    report = Gasola::ConsumptionReport.new(registration: @person.matricula, employee: @person, from: Date.new(2026, 9, 21), to: Date.new(2026, 10, 20))
    assert_equal ['TRANS-SUPPLY-9'], report.records.map(&:external_id)
    assert_equal 4, report.totals[:average]
  end

  test 'autonomy resolves the current profile and never reuses an old driver permission after transfer' do
    Employees::Registry.update!(@person, attributes: { operational_autonomy: '1' }, user: users(:one), reason: 'Autorização DU')
    driver = @person.drivers.first
    assert Employees::Registry.autonomy_record(@person.matricula).autonomy
    @person.change_role!({ sector: 'az', cargo: 'operador', turno: 0, starts_on: '2026-09-01', reason: 'Transferência' }, user: users(:one))
    operator = Employees::Registry.autonomy_record(@person.matricula)
    assert_instance_of Operator, operator
    refute operator.autonomy
    refute Autonomy.new(registration: @person.matricula, user: driver).valid?
    Employees::Registry.update!(@person, attributes: { operational_autonomy: '1' }, user: users(:one), reason: 'Autorização AZ')
    assert Autonomy.new(registration: @person.matricula, user: operator).valid?
    @person.retire!
    assert_nil Employees::Registry.autonomy_record(@person.matricula)
  end

  test 'a truncated source name cannot select an operator when another person has the same prefix' do
    @person.change_role!({ sector: 'az', cargo: 'operador', turno: 0, starts_on: '2026-09-01', reason: 'Transferência' }, user: users(:one))
    another = Employees::Registry.create!(attributes: { nome: 'Pessoa em transferência junior', matricula: 'TRANS-OTHER' },
      role: { sector: 'az', cargo: 'ajudante', turno: 1, starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
    assert_nil Employees::Registry.operator_for_name(@person.nome, date: @date)
    assert_equal another, EmployeeName.resolve(another.nome)
  end

  test 'reused registration aliases cannot expose another identity consumption history' do
    Employees::Registry.update!(@person, attributes: { matricula: 'TRANS-200' }, user: users(:one), reason: 'Matrícula corrigida')
    Employees::Registry.create!(attributes: { nome: 'Outra pessoa', matricula: 'TRANS-100' },
      role: { sector: 'du', cargo: 'motorista', promax: 'OTHER-PROMAX', starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
    GasolaSupply.create!(external_id: 'AMBIGUOUS-SUPPLY', registration: 'TRANS-100', concluded_at: Time.zone.local(2026, 10, 2, 12),
      status: 'CONCLUDED', category: 'veículo', fuel: 'dieselS10', liters: 100, distance: 400)
    report = Gasola::ConsumptionReport.new(registration: @person.matricula, employee: @person, from: Date.new(2026, 9, 21), to: Date.new(2026, 10, 20))
    assert_empty report.records
    assert_includes Employees::Audit.call[:overlapping_registration_aliases].flatten, @person.id
  end

  test 'an AZ role without a shift is rejected at the database boundary except for unknown legacy history' do
    @person.change_role!({ sector: 'az', cargo: 'operador', turno: 0, starts_on: '2026-09-01', reason: 'Transferência' }, user: users(:one))
    role = @person.employee_roles.az.first
    assert_raises(ActiveRecord::StatementInvalid) do
      EmployeeRole.transaction(requires_new: true) { role.update_columns(turno: nil) }
    end
    assert_equal 0, role.reload.turno
  end
end
