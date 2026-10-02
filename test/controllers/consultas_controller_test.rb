require "test_helper"

class ConsultasControllerTest < ActionDispatch::IntegrationTest
  setup { sign_out users(:one) }

  test "should get new" do
    get consultas_new_url
    assert_response :success
  end

  test "should get show" do
    get consultas_show_url, params: { matricula: drivers(:one).matricula, categoria: "motorista" }
    assert_response :success
  end
  test "employee driver sees only their consumption for the selected period" do
    employee = Employee.create!(nome: 'Motorista Gasola', matricula: 'TEST-GASOLA')
    employee.employee_roles.create!(cargo: 'motorista', promax: 'GASOLA-TEST', starts_on: '2026-01-01', reason: 'Admissão')
    GasolaSupply.create!(external_id: 'controller-test', registration: employee.matricula, plate: 'TEST-1234',
      concluded_at: Time.zone.local(2026, 9, 10), fuel: 'dieselS10', category: 'veículo', status: 'CONCLUDED',
      liters: 100, distance: 400, goal: 3.5)
    GasolaSupply.create!(external_id: 'other-driver', registration: 'OTHER', plate: 'OTHER-9999',
      concluded_at: Time.zone.local(2026, 9, 10), fuel: 'dieselS10', category: 'veículo', status: 'CONCLUDED',
      liters: 100, distance: 100, goal: 3.5)
    get consultas_show_url, params: { matricula: employee.matricula, categoria: 'motorista', periodo_mes: 9, periodo_ano: 2026 }
    assert_response :success
    assert_select 'section[aria-label="Meu consumo"]' do
      assert_select '.az-overview-value', text: '4,00 km/l'
      assert_select 'td', text: 'TEST-1234'
      assert_select 'td', text: 'OTHER-9999', count: 0
    end
  end

  test "helper does not see consumption card" do
    employee = Employee.create!(nome: 'Ajudante Gasola', matricula: 'TEST-HELPER')
    employee.employee_roles.create!(cargo: 'ajudante', promax: 'GASOLA-HELPER', starts_on: '2026-01-01', reason: 'Admissão')
    get consultas_show_url, params: { matricula: employee.matricula, categoria: 'ajudante', periodo_mes: 9, periodo_ano: 2026 }
    assert_response :success
    assert_select 'section[aria-label="Meu consumo"]', count: 0
  end

  test 'personal week and month are displayed without exposing the team calendar' do
    schedule = TimeOffSchedule.create!(name: 'Piloto', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
    schedule.time_off_memberships.create!(driver: drivers(:one), group_code: 'A', starts_on: schedule.starts_on)
    travel_to Time.zone.local(2026, 10, 2) do
      get consultas_show_url, params: { matricula: drivers(:one).matricula, categoria: 'motorista', periodo_mes: 9, periodo_ano: 2026 }
      assert_response :success
      assert_select 'section[aria-label="Minhas folgas"]' do
        assert_select '.personal-schedule__week .personal-schedule__day', count: 7
        assert_select '.personal-schedule__calendar .personal-schedule__day', count: 31
        assert_select '.personal-schedule__calendar [data-date="2026-10-06"] strong', text: 'Folga'
        assert_select 'summary', /Minha escala do mês/
        assert_select 'a[href*="escala-folgas"]', count: 0
      end
      get consultas_show_url, params: { matricula: drivers(:one).matricula, categoria: 'motorista', escala_mes: '2026-11' }
      assert_response :success
      assert_select 'details[open] .personal-schedule__calendar .personal-schedule__day', count: 30
    end
  end

  test 'RH helper sees own schedule and unregistered employee has a safe empty state' do
    employee = Employee.create!(nome: 'Ajudante Folgas', matricula: 'TEST-FOLGAS')
    employee.employee_roles.create!(cargo: 'ajudante', promax: 'TEST-FOLGAS', starts_on: '2026-01-01', reason: 'Admissão')
    ajudantes(:one).update!(employee: employee)
    travel_to Time.zone.local(2026, 10, 2) do
      get consultas_show_url, params: { matricula: employee.matricula, categoria: 'ajudante', escala_mes: 'invalid' }
      assert_response :success
      assert_select '.personal-schedule__empty', /não tem uma escala/
      schedule = TimeOffSchedule.create!(name: 'Piloto', starts_on: '2026-10-01', ends_on: '2026-10-31', rotation_anchor: '2026-09-28', recurring: true)
      schedule.time_off_memberships.create!(ajudante: ajudantes(:one), group_code: 'E', starts_on: schedule.starts_on)
      get consultas_show_url, params: { matricula: employee.matricula, categoria: 'ajudante' }
      assert_response :success
      assert_select '.personal-schedule__week [data-date="2026-10-02"] strong', text: 'Folga'
    end
  end

end
