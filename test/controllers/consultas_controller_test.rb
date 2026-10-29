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

  test 'legacy driver and helper consultations only show route maps' do
    driver = drivers(:one)
    helper = ajudantes(:one)
    driver.update!(matricula: 'AS-LEGACY-D', promax: 'AS-LEGACY-D')
    helper.update!(matricula: 'AS-LEGACY-H', promax: 'AS-LEGACY-H')
    %w[Rota AS].each do |delivery|
      Mapa.create!(mapa: "CONSULTA-#{delivery}", entrega: delivery, data: '10/09/2026',
        matric_motorista: driver.promax, matric_ajudante: helper.promax,
        fator: 1, cx_real: 10, pdv_total: 5, pdv_real: 5, recarga: 'NAO')
    end

    { 'motorista' => driver, 'ajudante' => helper }.each do |category, person|
      get consultas_show_url, params: { matricula: person.matricula, categoria: category, periodo_mes: 9, periodo_ano: 2026 }
      assert_response :success
      assert_select 'td[data-label="Mapa"]', text: 'CONSULTA-Rota', count: 1
      assert_select 'td[data-label="Mapa"]', text: 'CONSULTA-AS', count: 0
    end
  end

  test 'a driver with both Rota and AS keeps the same route amount in preview and closing' do
    employee = Employee.create!(nome: 'Motorista Rota e AS', matricula: 'MIXED-ROTA-AS')
    employee.employee_roles.create!(cargo: 'motorista', promax: 'MIXED-ROTA-AS', starts_on: '2026-01-01', reason: 'Admissão')
    { 'valor_caixa' => 1, 'valor_entrega' => 2, 'valor_recarga' => 80 }.each do |name, value|
      CalculationRateVersion.create!(categoria: 'motorista', nome: name, valor: value)
    end
    route_map = Mapa.create!(mapa: 'MIXED-ROTA', entrega: 'Rota', data: '10/09/2026',
      matric_motorista: employee.matricula, fator: 1, cx_real: 10, pdv_total: 5, pdv_real: 5, recarga: 'NAO')
    original_totals = EmployeeVariableReport.new(employee).totals
    assert_equal 20, original_totals[:valor_total]

    %w[NAO SIM].each do |refill|
      Mapa.create!(mapa: "MIXED-AS-#{refill}", entrega: 'AS', data: '11/09/2026',
        matric_motorista: employee.matricula, fator: 0, cx_real: 10000, pdv_total: 100, pdv_real: 0, recarga: refill)
    end
    assert_equal original_totals, EmployeeVariableReport.new(employee).totals

    get consultas_show_url, params: { matricula: employee.matricula, categoria: 'motorista', periodo_mes: 9, periodo_ano: 2026 }
    assert_response :success
    assert_select '.az-total-row--grand .az-total-amount', text: 'R$ 20,00'
    assert_select 'td[data-label="Mapa"]', text: 'MIXED-ROTA', count: 1
    assert_select 'td[data-label="Mapa"]', text: /MIXED-AS/, count: 0

    closing = VariableClosing.capture!(employee: employee, user: users(:one), year: 2026, month: 9, reason: 'Conferido Rota e AS')
    assert_equal 20, closing.result.dig('totals', 'valor_total').to_d
    assert_equal [route_map.id], closing.result.fetch('maps').map { |entry| entry.dig('source', 'id') }

    get consultas_show_url, params: { matricula: employee.matricula, categoria: 'motorista', periodo_mes: 9, periodo_ano: 2026 }
    assert_response :success
    assert_select '.az-total-row--grand .az-total-amount', text: 'R$ 20,00'
    assert_select 'td[data-label="Mapa"]', text: 'MIXED-ROTA', count: 1
    assert_select 'td[data-label="Mapa"]', text: /MIXED-AS/, count: 0
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
