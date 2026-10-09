require 'test_helper'

class EmployeeOnboardingTest < ActionDispatch::IntegrationTest
  setup { travel_to Time.zone.local(2026, 10, 9, 12) }
  teardown { travel_back }

  test 'registration exposes separate employment dates and allows an unknown function start' do
    get new_employee_path
    assert_response :success
    assert_select 'label[for=employee_registered_on]', text: 'Data de registro na carteira'
    assert_select 'input[name="employee[registered_on]"][type=date]'
    assert_select 'label[for=initial_starts_on]', text: 'Data de início na função'
    assert_select '#initial_starts_on[required]', count: 0
  end

  test 'a DU employee can be registered during integration without operational eligibility' do
    person = create_person
    assert_equal Date.new(2026, 10, 1), person.registered_on
    assert person.active?
    assert person.initial_role.pending_start?
    refute person.initial_role.legacy?
    assert_nil person.role_on(Date.current)
    %i[time_off pcd consumption az].each { |feature| refute person.eligible_for?(feature) }
    assert_nil Pcd::Board.new(date: Date.current).member("employee:#{person.id}")
    refute TimeOff::People.active_records(Driver).exists?(employee_id: person.id)
    refute TimeOff::GroupRoster.new(schedule: nil, date: Date.current).people.include?(person)
    refute EmployeeRole.on(Date.current).exists?(employee_id: person.id)
    refute EmployeeRole.during(Date.new(2026, 10, 1), Date.new(2026, 10, 31)).exists?(employee_id: person.id)
    assert_equal 'Em integração', person.employment_status_label

    get employee_path(person)
    assert_response :success
    assert_select '.employees-overview strong', text: 'Em integração'
    assert_select '.employees-overview strong', text: '01/10/2026'
    assert_select '.app-page-actions a[href*="escala-folgas"]', count: 0
    assert_select '#promotion_starts_on', count: 0
  end

  test 'an AZ employee awaiting a start has no AZ variable until the function begins' do
    person = create_person(sector: 'az', cargo: 'operador', registration: 'ONBOARD-AZ')
    assert_equal person.id, person.operators.first.employee_id
    refute person.eligible_for?(:az)
    report = AzVariableReport.new(person: person, from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 31))
    assert_empty report.daily
    assert_equal 0, report.total

    patch employee_path(person), params: { employee: { registered_on: '2026-10-01' },
      employee_role: { starts_on: '2026-10-09' }, reason: 'Integração concluída' }
    assert_redirected_to employee_path(person)
    assert person.reload.eligible_for?(:az)
    refute person.eligible_for?(:az, date: Date.new(2026, 10, 8))
  end

  test 'pending people remain visible and searchable in their intended sector' do
    du = create_person
    az = create_person(sector: 'az', cargo: 'operador', registration: 'ONBOARD-AZ')
    users(:one).update!(role: :supervisor, sector: :du)
    get employees_path, params: { cargo: 'motorista', q: 'ONBOARD' }
    assert_select '.employees-person strong', text: du.nome
    assert_select '.employees-person strong', text: az.nome, count: 0
    assert_select '.employees-status', text: 'Em integração'
    get employee_path(du)
    assert_response :success
    get employee_path(az)
    assert_response :forbidden

    users(:one).update!(sector: :warehouse)
    get employees_path, params: { cargo: 'operador', turno: '0' }
    assert_select '.employees-person strong', text: az.nome
    assert_select '.employees-person strong', text: du.nome, count: 0
  end

  test 'editing can leave the function start blank and audits the registration date' do
    person = create_person
    get edit_employee_path(person)
    assert_select '#employee_registered_on[value="2026-10-01"]'
    assert_select '#initial_starts_on[required]', count: 0
    patch employee_path(person), params: { employee: { registered_on: '2026-10-02' },
      employee_role: { starts_on: '' }, reason: 'Conferência da carteira' }
    assert_redirected_to employee_path(person)
    assert person.reload.initial_role.pending_start?
    event = person.employee_career_events.order(:id).last
    assert_equal '2026-10-01', event.details.dig('before', 'registered_on')
    assert_equal '2026-10-02', event.details.dig('after', 'registered_on')
    refute person.eligible_for?(:pcd)
  end

  test 'setting the initial function date preserves the role and releases the employee on that day' do
    person = create_person
    role_id = person.initial_role.id
    patch employee_path(person), params: { employee: { nome: 'Colaborador liberado' },
      employee_role: { starts_on: '2026-10-12' }, reason: 'Integração concluída' }
    assert_redirected_to employee_path(person)
    assert_equal role_id, person.reload.initial_role.id
    assert_equal 1, person.employee_roles.count
    refute person.initial_role.pending_start?
    assert_equal 'Colaborador liberado', person.drivers.first.nome
    assert_equal 'Em integração', person.employment_status_label
    assert_nil Pcd::Board.new(date: Date.new(2026, 10, 11)).member("employee:#{person.id}")
    assert Pcd::Board.new(date: Date.new(2026, 10, 12)).member("employee:#{person.id}")
    refute person.eligible_for?(:time_off, date: Date.new(2026, 10, 11))
    assert person.eligible_for?(:time_off, date: Date.new(2026, 10, 12))
    assert_equal 'Ativo', person.employment_status_label(date: Date.new(2026, 10, 12))
    event = person.employee_career_events.where("details ->> 'action' = 'revise_role'").last
    assert_equal true, event.details.dig('before', 0, 'pending_start')
    assert_equal '2026-10-12', event.details.dig('after', 0, 'starts_on')
  end

  test 'a future first role stays visible in RH without entering the operational roster' do
    person = create_person(starts_on: '2026-10-12')
    users(:one).update!(role: :supervisor, sector: :du)
    get employees_path, params: { cargo: 'motorista' }
    assert_select '.employees-person strong', text: person.nome
    get employee_path(person)
    assert_response :success
    assert_select '.employees-overview strong', text: '12/10/2026'
    refute person.eligible_for?(:pcd)
    assert person.eligible_for?(:pcd, date: Date.new(2026, 10, 12))
  end

  test 'the function cannot start before the registration and invalid creation rolls back adapters' do
    assert_no_difference(['Employee.count', 'EmployeeRole.count', 'Driver.count', 'EmployeeCareerEvent.count']) do
      post employees_path, params: registration_params(starts_on: '2026-09-30')
      assert_response :unprocessable_entity
      assert_select '[role=alert]', text: /deve ser igual ou posterior à data de registro na carteira/
      assert_select '#employee_registered_on[value="2026-10-01"]'
      assert_select '#initial_starts_on[value="2026-09-30"]'
    end
  end

  test 'an invalid completion rolls back identity dates role dates and audit rows together' do
    person = create_person
    assert_no_difference('EmployeeCareerEvent.count') do
      patch employee_path(person), params: { employee: { nome: 'Nome inválido', registered_on: '2026-10-10' },
        employee_role: { starts_on: '2026-10-09' }, reason: 'Datas incompatíveis' }
      assert_response :unprocessable_entity
    end
    person.reload
    assert_equal 'Pessoa ONBOARD-DU', person.nome
    assert_equal Date.new(2026, 10, 1), person.registered_on
    assert person.initial_role.pending_start?
    assert_equal person.nome, person.drivers.first.nome
  end

  test 'both dates can be corrected together without validating against the old function date' do
    person = create_person(starts_on: '2026-10-09')
    patch employee_path(person), params: { employee: { registered_on: '2026-10-12', operational_autonomy: '0' },
      employee_role: { starts_on: '2026-10-13' }, reason: 'Correção das datas' }
    assert_redirected_to employee_path(person)
    assert_equal Date.new(2026, 10, 12), person.reload.registered_on
    assert_equal Date.new(2026, 10, 13), person.initial_role.starts_on
    patch employee_path(person), params: { employee: { registered_on: '2026-10-01' },
      employee_role: { starts_on: '2026-10-02' }, reason: 'Conferência final' }
    assert_redirected_to employee_path(person)
    assert_equal Date.new(2026, 10, 2), person.reload.initial_role.starts_on
  end

  test 'registration-only edits cannot move admission beyond an existing function start' do
    person = create_person(starts_on: '2026-10-09')
    patch employee_path(person), params: { employee: { registered_on: '2026-10-10' }, reason: 'Data incorreta' }
    assert_response :unprocessable_entity
    assert_equal Date.new(2026, 10, 1), person.reload.registered_on
  end

  test 'invalid date text is rejected instead of silently creating an integration or releasing it' do
    assert_no_difference('Employee.count') do
      post employees_path, params: registration_params(starts_on: 'invalid')
      assert_response :unprocessable_entity
    end
    person = create_person
    patch employee_path(person), params: { employee: { registered_on: 'invalid' }, reason: 'Data inválida' }
    assert_response :unprocessable_entity
    assert_equal Date.new(2026, 10, 1), person.reload.registered_on
    patch employee_path(person), params: { employee: { nome: person.nome }, employee_role: { starts_on: 'invalid' }, reason: 'Data inválida' }
    assert_response :unprocessable_entity
    assert person.reload.initial_role.pending_start?
  end

  test 'integration cannot be bypassed by recording a new role' do
    person = create_person
    assert_no_difference('EmployeeRole.count') do
      post change_role_employee_path(person), params: { employee_role: {
        sector: 'du', cargo: 'motorista', promax: 'ONBOARD-OTHER', starts_on: '2026-10-09', reason: 'Movimentação antecipada'
      } }
      assert_redirected_to employee_path(person)
    end
    assert person.reload.initial_role.pending_start?
    assert_match(/Informe o início na função/, flash[:alert])
  end

  test 'pending roles are excluded from DU pay and cannot be made dated without clearing pending status' do
    person = create_person
    Mapa.create!(mapa: 'ONBOARD-MAP', data: '09/10/2026', matric_motorista: 'ONBOARD-DU',
      fator: 1, cx_real: 10, pdv_real: 5, pdv_total: 5, recarga: 'NAO')
    assert_empty EmployeeVariableReport.new(person).maps
    assert_raises(ActiveRecord::StatementInvalid) do
      EmployeeRole.transaction(requires_new: true) { person.initial_role.update_columns(starts_on: Date.current) }
    end
    assert person.reload.initial_role.pending_start?
  end

  test 'unknown legacy starts retain eligibility and are distinguished from a new integration' do
    person = Employee.create!(nome: 'Pessoa legada', matricula: 'ONBOARD-LEGACY')
    role = person.employee_roles.create!(sector: 'du', cargo: 'motorista', promax: 'ONBOARD-LEGACY', legacy: true, reason: 'Histórico legado')
    assert role.covers?(Date.current)
    assert person.eligible_for?(:pcd)
    assert_equal 'Ativo', person.employment_status_label
    assert EmployeeRole.on(Date.current).exists?(role.id)
    get edit_employee_path(person)
    assert_select '#initial_starts_on[required]', count: 0
    patch employee_path(person), params: { employee: { nome: 'Pessoa legada corrigida' },
      employee_role: { starts_on: '' }, reason: 'Correção de nome' }
    assert_redirected_to employee_path(person)
    assert_nil person.reload.initial_role.starts_on
    assert person.initial_role.legacy?
    assert person.eligible_for?(:pcd)
  end

  test 'sector and cargo are defined before integration without requiring Promax or shift' do
    { 'du' => %w[ajudante van motorista], 'az' => %w[ajudante operador] }.each do |sector, cargos|
      cargos.each do |cargo|
        person = create_person(sector: sector, cargo: cargo, registration: "PENDING-#{sector}-#{cargo}", operational_fields: false)
        role = person.initial_role
        assert_equal sector, role.sector
        assert_equal cargo, role.cargo
        assert role.pending_start?
        assert_nil role.promax
        assert_nil role.turno
        assert_nil role.starts_on
        get employee_path(person)
        assert_response :success
        assert_select '.employees-overview strong', text: role.label
        get employees_path, params: { employee_sector: sector, cargo: cargo, q: person.matricula }
        assert_select '.employees-person strong', text: person.nome
        assert_select "td[data-employee-id='#{person.id}']", text: ''
      end
    end
  end

  test 'DU operational fields can be filled after integration before assigning a group' do
    person = create_person(operational_fields: false)
    schedule = TimeOffSchedule.create!(name: 'Integração DU', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28')
    post assign_group_employee_path(person), params: { membership: { group_code: 'A', starts_on: '2026-10-09' } }
    assert_response :forbidden
    get edit_employee_path(person)
    assert_select '#initial_promax', count: 1
    assert_select 'input[name="employee_role[sector]"]', count: 0
    assert_select 'input[name="employee_role[cargo]"]', count: 0
    patch employee_path(person), params: { employee: { nome: person.nome },
      employee_role: { promax: 'AFTER-INTEGRATION', starts_on: '2026-10-09' }, reason: 'Integração concluída' }
    assert_redirected_to employee_path(person)
    assert_equal 'du', person.reload.initial_role.sector
    assert_equal 'motorista', person.initial_role.cargo
    assert_equal 'AFTER-INTEGRATION', person.drivers.first.promax
    assert person.eligible_for?(:pcd)
    post assign_group_employee_path(person), params: { membership: { group_code: 'A', starts_on: '2026-10-09' } }
    assert_redirected_to employees_path
    assert_equal 'A', schedule.time_off_memberships.find_by!(employee_id: person.id).group_code
  end

  test 'a pending AZ operator can receive a shift without changing the previously assigned cargo' do
    person = create_person(sector: 'az', cargo: 'operador', registration: 'PENDING-OPERATOR', operational_fields: false)
    patch employee_path(person), params: { employee: { nome: person.nome },
      employee_role: { turno: '2', starts_on: '' }, reason: 'Turno definido' }
    assert_redirected_to employee_path(person)
    assert person.reload.initial_role.pending_start?
    assert_equal 'operador', person.initial_role.cargo
    assert_equal 2, person.initial_role.turno
    assert_equal 2, person.operators.first.turno
    refute person.eligible_for?(:az)
    patch employee_path(person), params: { employee: { nome: person.nome },
      employee_role: { turno: '2', starts_on: '2026-10-09' }, reason: 'Integração concluída' }
    assert_redirected_to employee_path(person)
    assert person.reload.eligible_for?(:az)
    get edit_employee_path(person)
    assert_select '#initial_turno', count: 0
  end

  test 'starting the function requires DU Promax or an AZ shift and keeps the form editable on error' do
    %w[du az].each do |sector|
      person = create_person(sector: sector, cargo: sector == 'du' ? 'motorista' : 'operador',
        registration: "MISSING-#{sector}", operational_fields: false)
      patch employee_path(person), params: { employee: { nome: person.nome },
        employee_role: { starts_on: '2026-10-09' }, reason: 'Dados operacionais ausentes' }
      assert_response :unprocessable_entity
      assert person.reload.initial_role.pending_start?
      assert_select(sector == 'du' ? '#initial_promax' : '#initial_turno', count: 1)
    end
  end

  test 'a pending person without a Promax does not match maps with missing employee codes' do
    person = create_person(operational_fields: false)
    Mapa.create!(mapa: 'MISSING-CODE-MAP', data: '09/10/2026', matric_motorista: nil,
      fator: 1, cx_real: 10, pdv_real: 5, pdv_total: 5, recarga: 'NAO')
    assert_empty person.maps
    report = EmployeeVariableReport.new(person)
    assert_empty report.maps
    assert_empty report.issues
  end

  test 'editing identity after the function starts cannot rewrite operational codes' do
    person = create_person(starts_on: '2026-10-09')
    patch employee_path(person), params: { employee: { nome: 'Não alterar' },
      employee_role: { promax: 'REWRITE-HISTORY' }, reason: 'Troca sem movimentação' }
    assert_response :unprocessable_entity
    assert_equal 'ONBOARD-DU', person.reload.initial_role.promax
    assert_equal 'Pessoa ONBOARD-DU', person.nome
  end

  private

  def registration_params(sector: 'du', cargo: 'motorista', registration: 'ONBOARD-DU', starts_on: '', operational_fields: true)
    { employee: { nome: "Pessoa #{registration}", matricula: registration, registered_on: '2026-10-01' },
      employee_role: { sector: sector, cargo: cargo, promax: sector == 'du' && operational_fields ? registration : nil,
        turno: sector == 'az' && operational_fields ? 0 : nil, starts_on: starts_on } }
  end

  def create_person(**options)
    post employees_path, params: registration_params(**options)
    person = Employee.find_by!(matricula: options.fetch(:registration, 'ONBOARD-DU'))
    assert_redirected_to employee_path(person)
    person
  end
end
