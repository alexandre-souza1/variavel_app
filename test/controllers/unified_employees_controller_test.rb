require 'test_helper'

class UnifiedEmployeesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @person = Employees::Registry.create!(attributes: { nome: 'Pessoa AZ do RH', matricula: 'RH-AZ-100', data_nascimento: '1990-01-01' },
      role: { sector: 'az', cargo: 'ajudante', turno: 1, starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
  end

  test 'central ficha shows AZ fields and lets HR edit identity without offering PCD or scale' do
    get employee_path(@person)
    assert_response :success
    assert_select '.app-page-actions a[href*="escala-folgas"]', count: 0
    assert_select '#promotion_sector option[selected]', text: 'AZ'
    get edit_employee_path(@person)
    assert_response :success
    patch employee_path(@person), params: { employee: { nome: 'Pessoa corrigida' }, reason: 'Documento atualizado' }
    assert_redirected_to employee_path(@person)
    assert_equal 'Pessoa corrigida', @person.reload.nome
    assert_equal @person.nome, @person.az_ajudantes.first.nome
  end

  test 'the AZ movement form keeps the current cargo selected for a shift-only change' do
    @person.change_role!({ sector: 'az', cargo: 'operador', turno: 0, starts_on: '2026-08-01', reason: 'Cargo de operador' }, user: users(:one))
    get employee_path(@person)
    assert_select '#promotion_cargo option[selected]', text: 'Operador'
  end

  test 'DU users see only their sector even when requesting AZ filter and cannot edit careers' do
    du = Employees::Registry.create!(attributes: { nome: 'Pessoa DU do RH', matricula: 'RH-DU-100' },
      role: { cargo: 'motorista', promax: 'RH-DU-100', starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
    users(:one).update!(role: :user, sector: :du)
    get employees_path, params: { employee_sector: 'az' }
    assert_response :success
    assert_includes response.body, du.nome
    assert_not_includes response.body, @person.nome
    get employee_path(@person)
    assert_response :forbidden
    patch employee_path(du), params: { employee: { nome: 'Não permitido' }, reason: 'Tentativa' }
    assert_redirected_to root_path
    assert_equal 'Pessoa DU do RH', du.reload.nome
  end

  test 'central query automatically routes an AZ person and shows the same recorded total' do
    closing = VariableClosing.capture!(employee: @person, user: users(:one), year: 2026, month: 9, sector: 'az', reason: 'Conferência')
    get consulta_path, params: { matricula: @person.matricula, periodo_mes: 9, periodo_ano: 2026 }
    assert_redirected_to az_consulta_path(matricula: @person.matricula, periodo_mes: '9', periodo_ano: '2026')
    follow_redirect!
    assert_response :success
    assert_includes response.body, 'Fechamento registrado'
    assert_equal closing.result['total'].to_d, @person.variable_closings.where(sector: 'az').first.result['total'].to_d
  end

  test 'legacy ficha URLs redirect to the central identity and central new form' do
    get az_ajudante_path(@person.az_ajudantes.first)
    assert_redirected_to employee_path(@person, employee_sector: 'az')
    get new_az_ajudante_path
    assert_redirected_to new_employee_path(employee_sector: 'az', employee_cargo: 'ajudante')
  end

  test 'historic DU lookup keeps its sector in month navigation after an AZ transfer' do
    @person.change_role!({ sector: 'du', cargo: 'motorista', promax: 'HIST-DU', starts_on: '2026-08-01', reason: 'Transferência DU' }, user: users(:one))
    @person.change_role!({ sector: 'az', cargo: 'operador', turno: 0, starts_on: '2026-09-01', reason: 'Retorno AZ' }, user: users(:one))
    get consulta_path, params: { matricula: @person.matricula, employee_sector: 'du', periodo_mes: 8, periodo_ano: 2026 }
    assert_response :success
    assert_select '.az-period-filter input[name=employee_sector][value=du]'
  end

  test 'the old operator bulk retirement affects current operators and preserves transferred DU people' do
    @person.change_role!({ sector: 'az', cargo: 'operador', turno: 0, starts_on: '2026-08-01', reason: 'Função AZ' }, user: users(:one))
    @person.change_role!({ sector: 'du', cargo: 'motorista', promax: 'RETIRED-AZ', starts_on: '2026-09-01', reason: 'Transferência DU' }, user: users(:one))
    delete destroy_all_operators_path
    assert @person.reload.active?
    assert @person.operators.first.active?
  end

  test 'an AZ closing remains visible in its consultation dashboard and chat after a sector correction' do
    closing = VariableClosing.capture!(employee: @person, user: users(:one), year: 2026, month: 9, sector: 'az', reason: 'Conferência AZ')
    @person.revise_role!(@person.employee_roles.first.id, { sector: 'du', cargo: 'ajudante', promax: 'CORRECTED-DU', starts_on: '2026-01-01', reason: 'Correção de setor' }, user: users(:one))
    get az_consulta_path, params: { matricula: @person.matricula, periodo_mes: 9, periodo_ano: 2026 }
    assert_response :success
    assert_includes response.body, 'Fechamento registrado'
    row = AzDashboardService.new(start_date: Date.new(2026, 8, 19), end_date: Date.new(2026, 9, 18)).call.helpers.find { |entry| entry[:person].employee_id == @person.id }
    assert_equal closing.result['total'].to_d, row[:total]
    context = PublicVariableContext.new(PublicVariableIdentity.new('colaborador', @person)).call
    assert_equal closing.result['total'].to_f, context.dig(:data, :sectors, :az, :monthly, '2026-09', :total)
  end

  test 'meeting participant sources follow the canonical sector and cargo instead of old adapter tables' do
    @person.change_role!({ sector: 'du', cargo: 'motorista', promax: 'MEETING-DU', starts_on: '2026-09-01', reason: 'Transferência' }, user: users(:one))
    controller = MeetingMinutesController.new
    assert_includes controller.send(:participant_source_names, 'drivers', nil), @person.nome
    assert_not_includes controller.send(:participant_source_names, 'az_ajudantes', nil), @person.nome
  end
end
