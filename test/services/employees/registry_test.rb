require 'test_helper'

class EmployeesRegistryTest < ActiveSupport::TestCase
  def create_person(sector: 'du', cargo: 'motorista', turno: nil, matricula: 'UNIFIED-100')
    Employees::Registry.create!(attributes: { nome: 'Pessoa unificada', matricula: matricula, cpf: '12345678901', data_nascimento: '1990-01-01' },
      role: { sector: sector, cargo: cargo, promax: sector == 'du' ? matricula : nil, turno: turno,
        starts_on: '2026-01-01', reason: 'Admissão real' }, user: users(:one))
  end

  test 'RH creates a DU person visible in PCD and eligible for enrollment in the scale' do
    person = create_person
    assert_equal 1, person.drivers.count
    assert_equal person.nome, person.drivers.first.nome
    entry = Pcd::Board.new(date: Date.new(2026, 10, 2)).members.find { |member| member['person_key'] == "employee:#{person.id}" }
    assert_equal person.role_on(Date.new(2026, 10, 2)).promax, entry['code']
    schedule = TimeOffSchedule.create!(name: 'DU', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28')
    member = TimeOff::AssignGroup.call(schedule: schedule, person: person, group_code: 'A', starts_on: Date.new(2026, 10, 1), user: users(:one))
    assert_equal person.id, member.employee_id
    assert_equal "employee:#{person.id}", member.person_key
  end

  test 'AZ is registered centrally with a shift and without DU resources or a Promax' do
    person = create_person(sector: 'az', cargo: 'operador', turno: 1)
    assert_nil person.role_on(Date.current).promax
    assert_equal person.id, person.operators.first.employee_id
    assert person.eligible_for?(:az)
    refute person.eligible_for?(:pcd)
    refute person.eligible_for?(:time_off)
    refute person.eligible_for?(:consumption)
    refute Pcd::Board.new(date: Date.current).members.any? { |member| member['person_key'] == "employee:#{person.id}" }
    assert PublicVariableIdentity.find(profile: 'colaborador', registration: person.matricula, birth_date: '1990-01-01')
  end

  test 'identity changes preserve names and registrations and synchronize all compatibility records' do
    person = create_person
    person.change_role!({ sector: 'az', cargo: 'operador', turno: 2, starts_on: '2026-09-10', reason: 'Transferência' }, user: users(:one))
    Employees::Registry.update!(person, attributes: { nome: 'Nome corrigido', matricula: 'UNIFIED-200', cpf: '11122233344' }, user: users(:one), reason: 'Conferência de documentos')
    [person.drivers.first, person.operators.first].each do |record|
      assert_equal 'Nome corrigido', record.reload.nome
      assert_equal 'UNIFIED-200', record.matricula
    end
    assert_equal person, EmployeeName.resolve('Pessoa unificada')
    assert_includes person.registration_aliases, 'UNIFIED-100'
    assert_includes person.registration_aliases, 'UNIFIED-200'
    assert_equal 'update_identity', person.employee_career_events.order(:id).last.details['action']
  end

  test 'legacy retirement invalidates every adapter and existing public sessions' do
    person = create_person
    session = { 'profile' => 'colaborador', 'id' => person.id }
    assert PublicVariableIdentity.from_session(session)
    person.drivers.first.retire!
    refute person.reload.active?
    refute person.drivers.first.active?
    assert_nil PublicVariableIdentity.from_session(session)
    assert_nil PublicVariableIdentity.find(profile: 'motorista', registration: person.matricula, birth_date: '1990-01-01')
  end

  test 'legacy adapters reject undated code and shift changes' do
    person = create_person
    driver = person.drivers.first
    refute driver.update(promax: 'UNTRACKED')
    assert_equal 'UNIFIED-100', person.reload.role_on(Date.current).promax
    operator = create_person(sector: 'az', cargo: 'operador', turno: 0, matricula: 'AZ-100').operators.first
    refute operator.update(turno: 1)
  end

  test 'future transfer preserves DU eligibility and code until the effective day' do
    person = create_person
    person.change_role!({ sector: 'az', cargo: 'ajudante', turno: 0, starts_on: '2026-11-01', reason: 'Transferência agendada' }, user: users(:one))
    assert person.eligible_for?(:pcd, date: Date.new(2026, 10, 31))
    refute person.eligible_for?(:pcd, date: Date.new(2026, 11, 1))
    assert_equal 'UNIFIED-100', Pcd::Board.new(date: Date.new(2026, 10, 31)).member("driver:#{person.drivers.first.id}")['code']
  end

  test 'ambiguous names and registrations never choose a person arbitrarily' do
    person = create_person
    create_person(sector: 'az', cargo: 'operador', turno: 0, matricula: 'OTHER')
    assert_nil EmployeeName.resolve('Pessoa unificada')
    duplicate = Employee.create!(nome: 'Outra pessoa', matricula: 'OTHER-2', data_nascimento: person.data_nascimento)
    duplicate.update_column(:matricula, person.matricula)
    assert_nil PublicVariableIdentity.find(profile: 'colaborador', registration: person.matricula, birth_date: '1990-01-01')
  end
end
