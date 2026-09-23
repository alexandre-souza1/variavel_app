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
    assert_not_includes response.body, 'Registrar fechamento'
    assert_not_includes response.body, 'Motivo do fechamento ou revisão'
    assert_select '#promotion_cargo option[value="van"]', count: 0
    assert_select '#promotion_cargo option[value="motorista"]', count: 1
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
    assert_includes response.body, 'Parâmetros efetivamente usados no cálculo da função selecionada.'
    assert_includes response.body, 'Caixa real'
    assert_includes response.body, 'R$ 1,00'
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

  test 'consultation switch filters the whole report and offers all cargos' do
    CalculationRateVersion.create!(categoria: 'van', nome: 'valor_caixa', valor: 1)
    CalculationRateVersion.create!(categoria: 'van', nome: 'valor_entrega', valor: 2)
    CalculationRateVersion.create!(categoria: 'motorista', nome: 'valor_caixa', valor: 3)
    CalculationRateVersion.create!(categoria: 'motorista', nome: 'valor_entrega', valor: 4)
    @employee.change_role!({ cargo: 'motorista', promax: 'RH-MOTOR', starts_on: '2026-09-10', reason: 'Promoção' }, user: users(:one))
    Mapa.create!(mapa: 'RH-SWITCH-VAN', data: '09/09/2026', matric_motorista: 'RH-VAN', fator: 1, cx_real: 10, pdv_real: 5, pdv_total: 5, recarga: 'NAO')
    Mapa.create!(mapa: 'RH-SWITCH-MOTOR', data: '10/09/2026', matric_motorista: 'RH-MOTOR', fator: 1, cx_real: 10, pdv_real: 5, pdv_total: 5, recarga: 'NAO')
    VariableClosing.capture!(employee: @employee, user: users(:one), year: 2026, month: 9, reason: 'Fechamento')

    get consulta_path, params: { matricula: 'RH-100', categoria: 'colaborador', periodo_mes: 9, periodo_ano: 2026 }
    assert_response :success
    assert_includes response.body, 'Todos os cargos'
    assert_includes response.body, 'Motorista de van'
    assert_includes response.body, 'Motorista'
    assert_includes response.body, 'RH-SWITCH-VAN'
    assert_includes response.body, 'RH-SWITCH-MOTOR'
    assert_includes response.body, '<strong>2</strong> mapa(s)'

    get consulta_path, params: { matricula: 'RH-100', categoria: 'colaborador', periodo_mes: 9, periodo_ano: 2026, funcao: 'van' }
    assert_response :success
    assert_includes response.body, 'RH-SWITCH-VAN'
    assert_not_includes response.body, 'RH-SWITCH-MOTOR'
    assert_includes response.body, '<strong>1</strong> mapa(s)'
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
    @employee.update!(cpf: '01234567890')
    source = Employee.create!(nome: 'Mesmo Colaborador', matricula: 'RH-SOURCE', cpf: '1234567890')
    source.employee_roles.create!(cargo: 'motorista', promax: 'RH-SOURCE', legacy: true, reason: 'Migração')
    closing = VariableClosing.capture!(employee: source, user: users(:one), year: 2026, month: 8, reason: 'Histórico original')
    destination_closing = VariableClosing.capture!(employee: @employee, user: users(:one), year: 2026, month: 8, reason: 'Fechamento do cadastro principal')
    VariableClosing.where(id: closing.id).update_all(result: closing.result.merge('groups' => { 'motorista' => { 'quantidade_mapas' => 1, 'bonus_devolucao' => 10, 'valor_total' => 10 } }))
    VariableClosing.where(id: destination_closing.id).update_all(result: destination_closing.result.merge('groups' => { 'van' => { 'quantidade_mapas' => 1, 'bonus_devolucao' => 20, 'valor_total' => 20 } }))
    post link_record_employee_path(@employee), params: { source_employee_id: source.id, starts_on: '2026-09-10', reason: 'Vínculo e promoção' }
    assert_redirected_to employee_path(@employee)
    assert_equal 'motorista', @employee.reload.role_on(Date.new(2026, 9, 10)).cargo
    assert_equal source.id, closing.reload.employee_id
    assert_equal @employee.id, destination_closing.reload.employee_id
    assert_equal 2, @employee.variable_closings.where(year: 2026, month: 8).count
    assert_equal [1, 2], @employee.variable_closings.where(year: 2026, month: 8).order(:revision).pluck(:revision)
    consolidated = @employee.variable_closings.where(year: 2026, month: 8).order(:revision).last
    assert_equal %w[motorista van], consolidated.result.fetch('groups').keys.sort
    get employee_path(@employee)
    assert_select '.employees-closing', count: 1
    get employee_path(@employee), params: { cargo: 'van' }
    assert_select '.employees-closing', count: 1
    assert_select '.employees-closing td', text: 'Motorista de van', count: 1
    assert_select '.employees-closing td', text: 'Motorista', count: 0
    assert_empty source.employee_roles.reload
    assert_not source.reload.active?
  end

  test 'archived employees are separated from the active list' do
    @employee.update!(active: false)

    get employees_path
    assert_response :success
    assert_select 'h2', text: 'Encontre um colaborador'
    assert_not_includes response.body, @employee.nome

    get employees_path, params: { status: 'archived' }
    assert_response :success
    assert_select 'h2', text: 'Colaboradores arquivados'
    assert_includes response.body, @employee.nome
  end

  test 'link review resolves the same merge when opened from either cadastro' do
    @employee.update!(cpf: '12345678900')
    source = Employee.create!(nome: 'Cadastro legado', matricula: 'RH-SOURCE-REVERSE', cpf: '12345678900')
    source.employee_roles.create!(cargo: 'motorista', promax: 'RH-SOURCE-REVERSE', legacy: true, reason: 'Migração')
    driver = source.drivers.create!(nome: source.nome, matricula: source.matricula, promax: 'RH-SOURCE-REVERSE')

    get link_record_employee_path(source), params: { source_employee_id: @employee.id }
    assert_response :success
    assert_includes response.body, 'Cadastro principal'
    assert_includes response.body, @employee.nome
    assert_includes response.body, source.nome
    assert source.reload.active?
    assert_equal source.id, driver.reload.employee_id

    post link_record_employee_path(source), params: { source_employee_id: @employee.id, starts_on: '2026-09-10', reason: 'Vínculo conferido pelo RH' }
    assert_redirected_to employee_path(@employee)
    assert_equal 'motorista', @employee.reload.role_on(Date.new(2026, 9, 10)).cargo
    assert_equal @employee.id, driver.reload.employee_id
    assert_not source.reload.active?
  end

  test 'link review can invert two legacy records and preserve the progression order' do
    cpf = '98765432100'
    old_record = Employee.create!(nome: 'Ajudante legado', matricula: 'LEGACY-HELPER', cpf: cpf)
    old_record.employee_roles.create!(cargo: 'ajudante', promax: 'LEGACY-HELPER', legacy: true, reason: 'Migração')
    new_record = Employee.create!(nome: 'Van legado', matricula: 'LEGACY-VAN', cpf: cpf)
    new_record.employee_roles.create!(cargo: 'van', promax: 'LEGACY-VAN', legacy: true, reason: 'Migração')

    post link_record_employee_path(old_record), params: {
      source_employee_id: new_record.id, invert_positions: '1',
      starts_on: '2026-09-10', reason: 'Correção da direção do vínculo'
    }

    assert_redirected_to employee_path(new_record)
    assert_equal 'ajudante', new_record.reload.role_on(Date.new(2026, 9, 9)).cargo
    assert_equal 'van', new_record.role_on(Date.new(2026, 9, 10)).cargo
    assert_not old_record.reload.active?
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
    person = Employee.create!(nome: 'Histórico completo', matricula: 'RH-HISTORY')
    initial = person.change_role!({ cargo: 'ajudante', promax: 'RH-HISTORY', starts_on: '2026-01-01', reason: 'Admissão' }, user: users(:one))
    middle = person.change_role!({ cargo: 'van', promax: 'RH-HISTORY', starts_on: '2026-09-10', reason: 'Promoção' }, user: users(:one))
    person.change_role!({ cargo: 'motorista', promax: 'RH-HISTORY', starts_on: '2026-10-10', reason: 'Promoção' }, user: users(:one))
    [initial, middle].each do |role|
      delete delete_role_employee_path(person), params: { role_id: role.id }
      assert_redirected_to employee_path(person)
      assert EmployeeRole.exists?(role.id)
      assert flash[:alert].present?
    end
  end

  test 'a motorista cannot be moved back to van or ajudante' do
    @employee.change_role!({ cargo: 'motorista', promax: 'RH-VAN', starts_on: '2026-09-10', reason: 'Promoção' }, user: users(:one))

    assert_raises(EmployeeRole::HistoryError) do
      @employee.change_role!({ cargo: 'van', promax: 'RH-VAN', starts_on: '2026-10-10', reason: 'Correção indevida' }, user: users(:one))
    end
    assert_raises(EmployeeRole::HistoryError) do
      @employee.change_role!({ cargo: 'ajudante', promax: 'RH-VAN', starts_on: '2026-10-10', reason: 'Correção indevida' }, user: users(:one))
    end
    assert_equal 'motorista', @employee.reload.role_on(Date.new(2026, 10, 10)).cargo
  end

  test 'legacy closing can be revised from motorista to van without changing the old revision' do
    %w[motorista van].each do |cargo|
      CalculationRateVersion.create!(categoria: cargo, nome: 'valor_caixa', valor: 1)
      CalculationRateVersion.create!(categoria: cargo, nome: 'valor_entrega', valor: 2)
      CalculationRateVersion.create!(categoria: cargo, nome: 'valor_recarga', valor: 80)
    end
    CalculationRateVersion.create!(categoria: 'geral', nome: 'bonus_devolucao', valor: 100)
    mapa = Mapa.create!(mapa: 'LEGACY-CARGO', data: '01/09/2026', matric_motorista: 'RH-VAN', fator: 1,
      cx_real: 10, pdv_real: 5, pdv_total: 5, recarga: 'NAO')
    closing = VariableClosing.create!(employee: @employee, user: users(:one), year: 2026, month: 9, revision: 1,
      legacy_baseline: true, reason: 'Referência legada', result: {
        employee: @employee.attributes.slice('id', 'nome', 'matricula', 'cpf'),
        totals: { 'valor_total' => '30' },
        groups: { 'motorista' => { 'quantidade_mapas' => 1, 'bonus_devolucao' => '0', 'valor_total' => '30' } },
        maps: [{ source: mapa.attributes, calculation: { 'categoria' => 'motorista', 'role_id' => nil, 'valor_mp' => '30' } }],
        roles: [], issues: [], rule: 'Legado'
      })

    post revise_closing_employee_path(@employee), params: {
      closing_id: closing.id, from_cargo: 'motorista', to_cargo: 'van', reason: 'Correção do cargo legado'
    }

    assert_redirected_to employee_path(@employee)
    assert_equal 'motorista', closing.reload.result.dig('groups', 'motorista').present? && 'motorista'
    revised = @employee.variable_closings.where(year: 2026, month: 9).order(:revision).last
    assert_equal 2, revised.revision
    assert revised.result.dig('groups', 'van').present?
    assert_not revised.result.dig('groups', 'motorista').present?
    assert_equal 'van', revised.result.dig('maps', 0, 'calculation', 'categoria')
  end

end
