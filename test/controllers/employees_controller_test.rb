require 'test_helper'

class EmployeesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @employee = Employee.create!(nome: 'Colaborador RH', matricula: 'RH-100')
    @employee.change_role!({ cargo: 'van', promax: 'RH-VAN', starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
  end

  test 'RH pages and dated promotion work' do
    get employees_path
    assert_response :success
    get employee_path(@employee)
    assert_response :success
    post change_role_employee_path(@employee), params: { employee_role: { cargo: 'motorista', promax: 'RH-VAN', starts_on: '2026-09-10', reason: 'Promoção' } }
    assert_redirected_to employee_path(@employee)
    assert_equal 'motorista', @employee.reload.role_on(Date.new(2026, 9, 10)).cargo
    assert_equal 'van', @employee.role_on(Date.new(2026, 9, 9)).cargo
  end

  test 'unauthorized users cannot mutate careers' do
    users(:one).update!(role: :user, sector: :fleet)
    post change_role_employee_path(@employee), params: { employee_role: { cargo: 'motorista', starts_on: '2026-09-10', promax: 'X', reason: 'Teste' } }
    assert_redirected_to root_path
    assert_equal 1, @employee.employee_roles.count
  end

  test 'public report uses history regardless of category selected and keeps registered results' do
    CalculationRateVersion.create!(categoria: 'van', nome: 'valor_caixa', valor: 1)
    CalculationRateVersion.create!(categoria: 'van', nome: 'valor_entrega', valor: 2)
    mapa = Mapa.create!(mapa: 'RH-TEST', data: '01/09/2026', matric_motorista: 'RH-VAN', fator: 1, cx_real: 10, pdv_real: 5, pdv_total: 5, recarga: 'SIM')
    VariableClosing.capture!(employee: @employee, user: users(:one), year: 2026, month: 9, reason: 'Fechamento')
    mapa.update!(cx_real: 999)
    sign_out users(:one)
    get consulta_path, params: { matricula: 'RH-100', categoria: 'motorista', periodo_mes: 9, periodo_ano: 2026 }
    assert_response :success
    assert_select 'td', text: /Recarga informada; paga como mapa normal/
    assert_includes response.body, 'Fechamento registrado'
    assert_includes response.body, 'RH-TEST'
    assert_not_includes response.body, '>999'
  end
  test 'dashboard and chat use the employee role for van recarga' do
    CalculationRateVersion.create!(categoria: 'van', nome: 'valor_caixa', valor: 1)
    CalculationRateVersion.create!(categoria: 'van', nome: 'valor_entrega', valor: 2)
    Mapa.create!(mapa: 'RH-DASH', data: '01/09/2026', matric_motorista: 'RH-VAN', fator: 1, cx_real: 10, pdv_real: 5, pdv_total: 5, recarga: 'SIM')
    context = PublicVariableContext.new(PublicVariableIdentity.new('colaborador', @employee)).call
    assert_equal 20, context.dig(:data, :monthly, '2026-09', :total)
    get dashboard_mapas_path, params: { mes: 9, ano: 2026 }
    assert_response :success
    assert_includes response.body, 'Colaborador RH (Motorista de van)'
  end

  test 'new operational driver gets dated employee history' do
    post drivers_path, params: { driver: { nome: 'Nova Pessoa', matricula: 'RH-NEW', promax: 'RH-NEW', career_starts_on: '2026-09-10', career_cargo: 'van' } }
    assert_response :redirect
    person = Employee.find_by!(matricula: 'RH-NEW')
    assert_equal 'van', person.role_on(Date.new(2026, 9, 10)).cargo
    assert_nil person.role_on(Date.new(2026, 9, 9))
    assert_equal person.id, Driver.find_by!(matricula: 'RH-NEW').employee_id
  end

  test 'initial HR registration renders and creates employee' do
    get new_employee_path
    assert_response :success
    post employees_path, params: { employee: { nome: 'Novo RH', matricula: 'RH-CREATE' }, employee_role: { cargo: 'ajudante', promax: 'RH-CREATE', starts_on: '2026-09-01', reason: 'Admissão' } }
    assert_response :redirect
    assert_equal 'ajudante', Employee.find_by!(matricula: 'RH-CREATE').role_on(Date.new(2026, 9, 1)).cargo
  end

  test 'linking a legacy registration preserves original closings and records promotion' do
    @employee.update!(cpf: '12345678900')
    source = Employee.create!(nome: 'Mesmo Colaborador', matricula: 'RH-SOURCE', cpf: '12345678900')
    source.employee_roles.create!(cargo: 'motorista', promax: 'RH-SOURCE', legacy: true, reason: 'Migração')
    closing = VariableClosing.capture!(employee: source, user: users(:one), year: 2026, month: 8, reason: 'Histórico original')
    post link_record_employee_path(@employee), params: { source_employee_id: source.id, starts_on: '2026-09-10', reason: 'Vínculo e promoção' }
    assert_redirected_to employee_path(@employee)
    assert_equal 'motorista', @employee.reload.role_on(Date.new(2026, 9, 10)).cargo
    assert_equal source.id, closing.reload.employee_id
    assert_empty source.employee_roles.reload
    assert_not source.reload.active?
  end

  test 'CSV import rolls back all records if a career date is missing' do
    require 'tempfile'
    Tempfile.create(['career-import', '.csv']) do |file|
      file.write("matricula;promax;nome;inicio_cargo;cargo\nCSV-1;9001;Importado;2026-09-10;van\nCSV-2;9002;Sem Data;;motorista\n")
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, 'text/csv')
      assert_no_difference(['Employee.count', 'Driver.count', 'EmployeeRole.count']) do
        post import_csv_drivers_path, params: { file: upload }
      end
      assert_response :redirect
      assert flash[:alert].present?
    end
  end

  test 'duplicate registrations suggest a compatible source without changing records' do
    @employee.update!(cpf: '12345678900')
    source = Employee.create!(nome: 'Outro cadastro', matricula: 'TEMP-DUP', cpf: '123.456.789-00')
    source.employee_roles.create!(cargo: 'motorista', promax: 'DUP-CODE', legacy: true, reason: 'Legado')
    source.update_column(:matricula, @employee.matricula)
    get employees_path, params: { q: @employee.nome }
    assert_select 'a.employees-duplicate-link', count: 1
    get employee_path(@employee)
    assert_select '#cadastros-duplicados', count: 1
    assert_select 'a', text: 'Revisar e vincular'
    get employee_path(@employee), params: { source_employee_id: source.id }
    assert_select 'details#vincular-cadastro[open]', count: 1
    assert_select 'input[name="source_employee_id"][value="' + source.id.to_s + '"]'
    assert_equal 1, source.employee_roles.count
    source.employee_roles.destroy_all
    get employee_path(@employee)
    assert_select '#cadastros-duplicados', count: 0
  end

  test 'different CPF does not suggest a direct link' do
    source = Employee.create!(nome: 'Outra pessoa', matricula: 'TEMP-DUP', cpf: '99999999999')
    source.employee_roles.create!(cargo: 'motorista', promax: 'DUP-CODE', legacy: true, reason: 'Legado')
    source.update_column(:matricula, @employee.matricula)
    get employee_path(@employee), params: { source_employee_id: source.id }
    assert_select '#cadastros-duplicados', count: 1
    assert_select 'a', text: 'Revisar e vincular', count: 0
    assert_select 'details#vincular-cadastro[open]', count: 0
  end

  test 'admin author can remove the latest promotion and preserve closing' do
    role = @employee.change_role!({ cargo: 'motorista', promax: 'RH-VAN', starts_on: '2026-09-10', reason: 'Promoção' }, user: users(:one))
    closing = VariableClosing.capture!(employee: @employee, user: users(:one), year: 2026, month: 9, reason: 'Conferência')
    original = closing.result.deep_dup
    get employee_path(@employee)
    assert_select 'button', text: /Excluir movimentação/
    delete delete_role_employee_path(@employee), params: { role_id: role.id }
    assert_redirected_to employee_path(@employee)
    assert_not EmployeeRole.exists?(role.id)
    assert_equal 'van', @employee.reload.role_on(Date.new(2026, 9, 11)).cargo
    assert_nil @employee.employee_roles.first.ends_on
    assert_equal original, closing.reload.result
    assert_equal 'delete_role', @employee.employee_career_events.order(:id).last.details['action']
  end

  test 'another admin and a non-admin author cannot delete promotion' do
    role = @employee.change_role!({ cargo: 'motorista', promax: 'RH-VAN', starts_on: '2026-09-10', reason: 'Promoção' }, user: users(:two))
    delete delete_role_employee_path(@employee), params: { role_id: role.id }
    assert_response :forbidden
    assert EmployeeRole.exists?(role.id)
    role.update!(created_by: users(:one))
    users(:one).update!(role: :supervisor)
    delete delete_role_employee_path(@employee), params: { role_id: role.id }
    assert_response :forbidden
    assert EmployeeRole.exists?(role.id)
  end

  test 'initial and intermediate roles cannot be deleted' do
    initial = @employee.employee_roles.first
    middle = @employee.change_role!({ cargo: 'motorista', promax: 'RH-VAN', starts_on: '2026-09-10', reason: 'Promoção' }, user: users(:one))
    @employee.change_role!({ cargo: 'van', promax: 'RH-VAN', starts_on: '2026-10-10', reason: 'Mudança' }, user: users(:one))
    [initial, middle].each do |role|
      delete delete_role_employee_path(@employee), params: { role_id: role.id }
      assert_redirected_to employee_path(@employee)
      assert EmployeeRole.exists?(role.id)
      assert flash[:alert].present?
    end
  end

end
