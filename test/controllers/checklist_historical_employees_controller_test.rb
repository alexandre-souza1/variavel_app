require 'test_helper'

class ChecklistHistoricalEmployeesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @task = tasks(:one)
    @task.update!(title: 'Aplicar matriz ao motorista Ex Motorista Histórico por não realização do Checklist de Saída no dia 14/03/2026', description: nil)
    @filters = { year: 2026, action_plan_id: @task.bucket.action_plan_id, employee_sector: 'du' }
    @attributes = { nome: 'Ex Motorista Histórico', profile: 'du_motorista' }
  end

  test 'historical registration is discoverable from review and preserves task context and filters' do
    get checklist_occurrences_path(@filters.merge(display: 'review'))
    assert_response :success
    assert_select "a[href=?]", new_checklist_historical_employee_path(@filters), text: 'Cadastrar ex-colaborador'
    get new_checklist_historical_employee_path(@filters.merge(task_id: @task.id))
    assert_response :success
    assert_select 'h1', text: 'Cadastrar ex-colaborador'
    assert_select 'input[name=task_id][value=?]', @task.id.to_s
    assert_select 'input[name=year][value="2026"]'
    assert_select 'input[name="historical_employee[matricula]"][required]', count: 0
    assert_select 'input[name="historical_employee[starts_on]"][required]', count: 0
    assert_select 'p', text: /Ação de referência:.*Ex Motorista Histórico/
  end

  test 'modal endpoint renders only the shared dialog with context and field values' do
    get new_checklist_historical_employee_path(@filters.merge(task_id: @task.id)), headers: { 'X-Requested-With' => 'XMLHttpRequest' }
    assert_response :success
    assert_select '#historicalEmployeeModal.modal.app-modal', count: 1
    assert_select '.modal-dialog-scrollable form.modal-content', count: 1
    assert_select '.modal-header h2', text: 'Cadastrar ex-colaborador'
    assert_select '.modal-body input[name=task_id][value=?]', @task.id.to_s
    assert_select '.modal-footer button[data-bs-dismiss=modal]', text: 'Cancelar'
    assert_select '.app-page', count: 0
    assert_not_includes response.body, '<html'
  end

  test 'modal save returns the identity without navigating and validation stays in the dialog' do
    assert_difference('Employee.count', 1) do
      post checklist_historical_employees_path, params: @filters.merge(historical_employee: @attributes), as: :json
    end
    assert_response :created
    person = Employee.find_by!(nome: @attributes[:nome])
    assert_equal person.id, response.parsed_body.dig('employee', 'id')
    assert_equal person.checklist_identity_label, response.parsed_body.dig('employee', 'label')
    assert_nil response.headers['Location']
    assert_no_difference('Employee.count') do
      post checklist_historical_employees_path, params: @filters.merge(task_id: @task.id, historical_employee: @attributes), as: :json
    end
    assert_response :unprocessable_entity
    fragment = Nokogiri::HTML.fragment(response.parsed_body.fetch('html'))
    assert fragment.at_css('#historicalEmployeeModal .modal-body .alert-danger')
    assert_equal @attributes[:nome], fragment.at_css('input[name="historical_employee[nome]"]')['value']
    assert_equal 'du_motorista', fragment.at_css('select[name="historical_employee[profile]"] option[selected]')['value']
    assert_equal @task.id.to_s, fragment.at_css('input[name=task_id]')['value']
  end

  test 'one inactive historical person unlocks batch recognition across their old tasks' do
    duplicate = @task.bucket.tasks.create!(title: @task.title, creator: users(:one))
    second_date = @task.bucket.tasks.create!(title: @task.title.sub('14/03/2026', '15/03/2026'), creator: users(:one))
    assert_difference('Employee.count', 1) do
      assert_no_difference('ChecklistOccurrence.count') do
        post checklist_historical_employees_path, params: @filters.merge(task_id: @task.id, historical_employee: @attributes)
      end
    end
    assert_redirected_to checklist_occurrences_path(@filters.merge(display: 'review'))
    person = Employee.find_by!(nome: @attributes[:nome])
    follow_redirect!
    assert_select "select[name='checklist_occurrence[employee_id]'] option[selected][value='#{person.id}']", count: 3
    assert_select "option[value='#{person.id}']", text: /Sem matrícula.*Ex-colaborador/, minimum: 3
    assert_difference('ChecklistOccurrence.count', 3) do
      post identify_checklist_occurrences_path, params: @filters.merge(display: 'review')
    end
    assert_equal [@task.id, duplicate.id, second_date.id].sort, person.checklist_occurrences.pluck(:task_id).sort
    get checklist_occurrences_path(@filters)
    assert_select '.checklist-tracking__ranking tbody tr', count: 1
    assert_select '.checklist-tracking__ranking .checklist-tracking__total', text: '2'
    assert_select '.employees-code', text: 'Sem matrícula'
    get employees_path(q: person.nome)
    assert_select '.employees-person', count: 0
    get employees_path(q: person.nome, status: 'archived')
    assert_select '.employees-person', text: /Ex Motorista Histórico/
    get employee_path(person)
    assert_response :success
    assert_select '.alert-info', text: /Cadastro histórico/
    assert_select "form[action=?]", reactivate_employee_path(person), count: 0
    get edit_employee_path(person)
    assert_response :success
    assert_select '#employee_matricula[required]', count: 0
    patch reactivate_employee_path(person)
    assert_response :redirect
    assert_not person.reload.active?
  end

  test 'invalid and duplicate historical registrations preserve input without orphan records' do
    post checklist_historical_employees_path, params: @filters.merge(historical_employee: @attributes.merge(ends_on: '2026-02-30'))
    assert_response :unprocessable_entity
    assert_select '.alert-danger', text: /datas válidas/
    assert_select 'input[name="historical_employee[nome]"][value=?]', @attributes[:nome]
    assert_select 'input[name=action_plan_id][value=?]', @task.bucket.action_plan_id.to_s
    assert_not Employee.exists?(nome: @attributes[:nome])
    post checklist_historical_employees_path, params: @filters.merge(historical_employee: @attributes)
    assert_no_difference(['Employee.count', 'EmployeeRole.count', 'EmployeeCareerEvent.count']) do
      post checklist_historical_employees_path, params: @filters.merge(historical_employee: @attributes)
    end
    assert_response :unprocessable_entity
    assert_select '.alert-danger', text: /Já existe um cadastro com este nome/
  end

  test 'historical helper DU can be selected but their checklist occurrence is rejected' do
    post checklist_historical_employees_path, params: @filters.merge(historical_employee: @attributes.merge(profile: 'du_ajudante'))
    person = Employee.find_by!(nome: @attributes[:nome])
    assert_no_difference('ChecklistOccurrence.count') do
      post task_checklist_occurrences_path(@task), params: { checklist_occurrence: { employee_id: person.id, occurred_on: '2026-03-14', checklist_kind: 'saida' } }, as: :turbo_stream
    end
    assert_select '#task-checklist-occurrences-' + @task.id.to_s, text: /Ajudante DU não realiza checklist/
  end

  test 'fleet readers and operational readers cannot create historical RH records' do
    users(:one).update!(role: :user, sector: :fleet)
    get checklist_occurrences_path(year: 2026, display: 'review')
    assert_response :success
    assert_select 'a', text: 'Cadastrar ex-colaborador', count: 0
    get new_checklist_historical_employee_path
    assert_response :forbidden
    assert_no_difference('Employee.count') do
      post checklist_historical_employees_path, params: { historical_employee: @attributes }
    end
    assert_response :forbidden
  end

  test 'sector limited managers cannot register historical people in another sector or open private tasks' do
    users(:one).update!(role: :supervisor, sector: :du)
    get new_checklist_historical_employee_path
    assert_response :success
    assert_select "select[name='historical_employee[profile]'] option[value^='az_']", count: 0
    assert_no_difference('Employee.count') do
      post checklist_historical_employees_path, params: { historical_employee: @attributes.merge(profile: 'az_operador') }
    end
    assert_response :unprocessable_entity
    private_plan = users(:two).action_plans.create!(name: 'Privado', public: false, sector: :warehouse)
    private_task = private_plan.buckets.first.tasks.create!(title: 'Ação privada', creator: users(:two))
    get new_checklist_historical_employee_path(task_id: private_task.id)
    assert_response :not_found
  end
end
