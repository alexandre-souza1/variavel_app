require 'test_helper'

class HistoricalRegistrationTest < ActiveSupport::TestCase
  def registration(**attributes)
    Employees::HistoricalRegistration.new({ nome: 'Pessoa Histórica sem Cadastro', profile: 'du_motorista' }.merge(attributes))
  end

  test 'historical person requires neither invented dates nor operational identifiers and is auditable' do
    form = registration
    assert_difference('Employee.count', 1) do
      assert_no_difference(['Driver.count', 'Ajudante.count', 'Operator.count', 'AzAjudante.count', 'ChecklistOccurrence.count']) do
        assert form.save(user: users(:one)), form.errors.full_messages.to_sentence
      end
    end
    person = form.employee.reload
    assert person.historical_only?
    assert_not person.active?
    assert_nil person.matricula
    assert_nil person.retired_at
    assert_nil person.initial_role.starts_on
    assert_nil person.initial_role.ends_on
    assert_nil person.initial_role.promax
    assert person.initial_role.legacy?
    assert_not person.initial_role.pending_start?
    assert_includes Employee.archived, person
    assert_not_includes Employee.active, person
    assert_equal [person.id], EmployeeName.owners(person.nome)
    assert_equal 'historical_registration', person.employee_career_events.last.details['action']
    assert_not person.eligible_for?(:time_off)
    assert_not person.eligible_for?(:consumption)
    assert_not person.operational_autonomy
    assert ChecklistTracking::Eligibility.new(employee: person, date: Date.new(2026, 3, 14)).allows?('saida')
    assert_not person.update(active: true)
    assert_includes person.errors.full_messages.join, 'deve permanecer inativo'
  end

  test 'all historical roles preserve checklist rules and access by sector' do
    expected = { 'du_motorista' => %w[saida retorno], 'du_van' => nil, 'du_ajudante' => [], 'az_ajudante' => %w[paleteira], 'az_operador' => %w[empilhadeira] }
    expected.each do |profile, kinds|
      form = registration(nome: "Histórico #{profile}", profile: profile)
      assert form.save(user: users(:one)), form.errors.full_messages.to_sentence
      assert_equal kinds, ChecklistTracking::Eligibility.new(employee: form.employee, date: Date.new(2026, 3, 14)).allowed_kinds
      sector = profile.start_with?('az') ? 'az' : 'du'
      assert_includes Employee.in_current_or_last_sector(sector), form.employee
    end
  end

  test 'known historical period is respected and invalid dates never silently become unknown' do
    form = registration(starts_on: '2025-01-10', ends_on: '2026-05-31')
    assert form.save(user: users(:one)), form.errors.full_messages.to_sentence
    assert_equal Date.new(2026, 5, 31), form.employee.retired_at
    assert_not ChecklistTracking::Eligibility.new(employee: form.employee, date: Date.new(2026, 6, 1)).allows?('saida')
    assert_not ChecklistTracking::Eligibility.new(employee: form.employee, date: Date.new(2025, 1, 9)).allows?('saida')
    [ { starts_on: 'invalid' }, { ends_on: '2026-02-30' }, { starts_on: '2026-05-01', ends_on: '2026-04-01' }, { ends_on: Date.current + 1 } ].each do |attributes|
      invalid = registration(nome: 'Outra pessoa', **attributes)
      assert_no_difference('Employee.count') { assert_not invalid.save(user: users(:one)) }
    end
  end

  test 'identity checks reuse existing records and do not guess who a namesake is' do
    existing = Employee.create!(nome: 'Pessoa Existente', matricula: 'HIST-EXISTING')
    [ { nome: existing.nome }, { nome: 'Outro Nome', matricula: existing.matricula } ].each do |attributes|
      form = registration(**attributes)
      assert_no_difference('Employee.count') { assert_not form.save(user: users(:one)) }
    end
    homonym = registration(nome: existing.nome, matricula: 'HIST-OTHER')
    assert homonym.save(user: users(:one)), homonym.errors.full_messages.to_sentence
    assert_equal :ambiguous, ChecklistTracking::NameMatcher.new([existing, homonym.employee]).call(name: existing.nome).confidence
    unknown = registration(nome: 'Sem matrícula anterior')
    assert unknown.save(user: users(:one))
    assert_not registration(nome: unknown.nome, matricula: 'HIST-NOW-KNOWN').save(user: users(:one))
  end

  test 'historical exception does not loosen normal employee or role requirements' do
    assert_not Employee.new(nome: 'Normal').valid?
    person = Employee.create!(nome: 'Cadastro Normal', matricula: 'NORMAL-HIST')
    role = person.employee_roles.new(cargo: 'motorista', sector: 'du', legacy: true, reason: 'Importação')
    assert_not role.valid?
    assert role.errors[:promax].any?
    assert_raises(ActiveRecord::NotNullViolation, ActiveRecord::StatementInvalid) do
      Employee.transaction(requires_new: true) { Employee.insert_all!([{ nome: 'Sem identidade', active: true, historical_only: false }]) }
    end
  end

  test 'creation cannot cross employee sector permissions or grant RH writes to fleet' do
    user = users(:two)
    user.update!(role: :supervisor, sector: :du)
    assert_not registration(profile: 'az_operador').save(user: user)
    user.update!(role: :user, sector: :fleet)
    assert_not registration.save(user: user)
  end
end
