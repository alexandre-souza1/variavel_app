require "test_helper"

class ChecklistOccurrencesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.update!(name: "Gestor")
    @employee = Employee.create!(nome: "Pessoa Checklist", matricula: "OCC-01")
    @task = tasks(:one)
    @task.update!(title: "Aplicar matriz ao motorista Pessoa Checklist por não realização do Checklist de Saída no dia 14/03/2026", description: nil)
    @attributes = { employee_id: @employee.id, occurred_on: "2026-03-14", checklist_kind: "saida" }
  end

  test "review tab shows candidates without treating suggestions as confirmed absences" do
    get checklist_occurrences_path(year: 2026, display: "review")
    assert_response :success
    assert_select ".checklist-tracking__metrics strong", text: "0"
    assert_select ".checklist-tracking__candidate strong", text: @task.title
    assert_select "select[name='checklist_occurrence[employee_id]'] option[selected][value='#{@employee.id}']"
    assert_select "input[name='checklist_occurrence[occurred_on]'][value='2026-03-14']"
    assert_equal 0, ChecklistOccurrence.count
    assert_not_includes response.body, "Sugerir com Gemini"
  end

  test "review queue displays badges while collapsed and prefills the job inferred checklist" do
    @employee.change_role!({ cargo: "operador", sector: "az", turno: 0, starts_on: "2026-01-01", reason: "Admissão" }, user: @user)
    @employee.update!(nome: "Rafael de Souza")
    @task.update!(title: "Aplicar matriz ao operador Rafael por não realização do Checklist no dia 16/05/2026")
    @task.labels << @task.bucket.action_plan.labels.create!(name: "AZ", color: "#00aa55")
    get checklist_occurrences_path(year: 2026, display: "review")
    assert_response :success
    assert_select ".checklist-tracking__candidate summary .task-label-badge", text: "AZ"
    assert_select "select[name='checklist_occurrence[employee_id]'] option[selected][value='#{@employee.id}']"
    assert_select "select[name='checklist_occurrence[checklist_kind]'] option[selected][value='empilhadeira']"
    assert_select "form[action=?] input[type=submit], form[action=?] button", identify_checklist_occurrences_path, identify_checklist_occurrences_path, text: /Registrar 1 identificada/
  end

  test "tabs display only their own content and preserve filters" do
    @employee.change_role!({ cargo: "motorista", sector: "du", promax: "TABS-DU", starts_on: "2026-01-01", reason: "Admissão" }, user: @user)
    @task.checklist_occurrences.create!(@attributes.merge(recorded_by: @user))
    %w[annual calendar history review].each do |display|
      get checklist_occurrences_path(year: 2026, employee_sector: "du", employee_id: @employee.id,
        action_plan_id: @task.bucket.action_plan_id, month: 3, display: display)
      assert_response :success
      assert_select "#tracking-overview", count: %w[annual calendar].include?(display) ? 1 : 0
      assert_select "#tracking-history", count: display == "history" ? 1 : 0
      assert_select "#tracking-review", count: display == "review" ? 1 : 0
      assert_select "#tracking-navigation a[aria-current=page]", count: 1
      assert_select "input[name=display][value=?]", display
      assert_select "#tracking-navigation a", count: 4 do |links|
        links.each do |link|
          query = Rack::Utils.parse_query(URI.parse(link["href"]).query)
          assert_equal "du", query["employee_sector"]
          assert_equal "2026", query["year"]
          assert_equal "3", query["month"]
          assert_equal @employee.id.to_s, query["employee_id"]
          assert_equal @task.bucket.action_plan_id.to_s, query["action_plan_id"]
        end
      end
    end
  end

  test "clear cases can be registered in a single batch without individual corrections" do
    get checklist_occurrences_path(year: 2026, display: "review")
    assert_select "form[action=?] input[type=submit], form[action=?] button", identify_checklist_occurrences_path, identify_checklist_occurrences_path, text: /Registrar 1 identificada/
    assert_difference("ChecklistOccurrence.count", 1) do
      post identify_checklist_occurrences_path, params: { year: 2026, action_plan_id: @task.bucket.action_plan_id }
    end
    assert_redirected_to checklist_occurrences_path(year: 2026, action_plan_id: @task.bucket.action_plan_id)
    assert_no_difference("ChecklistOccurrence.count") do
      post identify_checklist_occurrences_path, params: { year: 2026 }
    end
  end

  test "registration from dashboard refreshes totals and preserves chosen year" do
    assert_difference(["ChecklistOccurrence.count", "TaskActivity.count"], 1) do
      post task_checklist_occurrences_path(@task), params: { checklist_occurrence: @attributes,
        tracking_dashboard: "1", year: 2026, display: "review" }
    end
    assert_redirected_to checklist_occurrences_path(year: 2026, display: "review")
    follow_redirect!
    assert_response :success
    assert_select "#tracking-review"
    assert_select ".checklist-tracking__candidate strong", text: @task.title, count: 0
    get checklist_occurrences_path(year: 2026)
    assert_select ".checklist-tracking__ranking tbody tr", count: 1
    assert_select ".checklist-tracking__ranking .checklist-tracking__total", text: "1"
    get checklist_occurrences_path(year: 2026, display: "history")
    assert_select ".checklist-tracking__event a", text: @task.title
    assert_equal @user, ChecklistOccurrence.last.recorded_by
    assert_equal "checklist_occurrence", TaskActivity.last.metadata["field"]
  end

  test "task modal stays separate from tracking while registration and cancellation retain their audit trail" do
    get task_path(@task)
    assert_response :success
    assert_select "#task-checklist-occurrences-#{@task.id}", count: 0
    assert_select '.checklist-tracking__registration', count: 0
    post task_checklist_occurrences_path(@task), params: { checklist_occurrence: @attributes }, as: :turbo_stream
    assert_response :success
    record = ChecklistOccurrence.last
    assert_select "turbo-stream[target='task-checklist-occurrences-#{@task.id}']"
    assert_no_difference("ChecklistOccurrence.count") do
      patch cancel_task_checklist_occurrence_path(@task, record), params: { cancellation_reason: "Pessoa incorreta" }, as: :turbo_stream
    end
    assert_response :success
    assert record.reload.cancelled_at?
    assert_equal "Pessoa incorreta", record.cancellation_reason
    assert_equal @user, record.cancelled_by
    assert_equal "cancelled", TaskActivity.last.metadata["action"]
    assert_no_difference("TaskActivity.count") do
      patch cancel_task_checklist_occurrence_path(@task, record), params: { cancellation_reason: "Repetição" }, as: :turbo_stream
    end
  end

  test "invalid duplicate and empty cancellation do not change counts" do
    post task_checklist_occurrences_path(@task), params: { checklist_occurrence: @attributes }, as: :turbo_stream
    record = ChecklistOccurrence.last
    assert_no_difference("ChecklistOccurrence.count") do
      post task_checklist_occurrences_path(@task), params: { checklist_occurrence: @attributes }, as: :turbo_stream
    end
    assert_match "já registrado", response.body
    patch cancel_task_checklist_occurrence_path(@task, record), params: { cancellation_reason: "   " }, as: :turbo_stream
    assert_nil record.reload.cancelled_at
    assert_select "#task-checklist-occurrences-#{@task.id} .alert-danger", text: /Motivo/
  end

  test "different people and types can be tracked in the same task and filtered" do
    other = Employee.create!(nome: "Outra Pessoa", matricula: "OCC-02")
    [@attributes, @attributes.merge(employee_id: other.id), @attributes.merge(checklist_kind: "retorno")].each do |attributes|
      post task_checklist_occurrences_path(@task), params: { checklist_occurrence: attributes }
    end
    get checklist_occurrences_path(year: 2026, employee_id: @employee.id, month: 3, display: "history")
    assert_response :success
    assert_select ".checklist-tracking__event", count: 2
    assert_select ".checklist-tracking__ranking", count: 0
    get checklist_occurrences_path(year: "invalid")
    assert_response :success
    assert_select "input[name=year][value='#{Date.current.year}']"
  end

  test "mechanics and logged out visitors cannot access tracking" do
    @user.update!(role: :mechanical)
    get checklist_occurrences_path
    assert_response :forbidden
    post task_checklist_occurrences_path(@task), params: { checklist_occurrence: @attributes }
    assert_response :forbidden
    post identify_checklist_occurrences_path, params: { year: 2026 }
    assert_response :forbidden
    sign_out @user
    get checklist_occurrences_path
    assert_redirected_to new_user_session_path
  end

  test "module counts follow employee sectors while private action details remain protected" do
    @employee.change_role!({ cargo: "motorista", sector: "du", promax: "OCC-DU", starts_on: "2026-01-01", reason: "Admissão" }, user: @user)
    other_employee = Employee.create!(nome: "Pessoa de Outro Setor", matricula: "OCC-AZ")
    other_employee.change_role!({ cargo: "operador", sector: "az", turno: 0, starts_on: "2026-01-01", reason: "Admissão" }, user: @user)
    @task.checklist_occurrences.create!(@attributes.merge(recorded_by: @user))
    @task.checklist_occurrences.create!(@attributes.merge(employee_id: other_employee.id, checklist_kind: "empilhadeira", recorded_by: @user))
    outsider = users(:two)
    outsider.update!(role: :user, sector: :warehouse)
    private_plan = outsider.action_plans.create!(name: "Histórico Privado", sector: :warehouse, public: false)
    private_task = private_plan.buckets.first.tasks.create!(title: "Falta que não pode aparecer", creator: outsider)
    private_task.checklist_occurrences.create!(@attributes.merge(occurred_on: "2026-04-01", recorded_by: outsider))
    @user.update!(role: :user, sector: :du)
    sign_in @user
    get checklist_occurrences_path(year: 2026)
    assert_response :success
    assert_select ".checklist-tracking__metrics strong:first-of-type", text: "2", minimum: 1
    assert_select ".checklist-tracking__ranking tbody tr", count: 1
    assert_not_includes response.body, other_employee.nome
    assert_not_includes response.body, private_task.title
    get checklist_occurrences_path(year: 2026, display: "history")
    assert_not_includes response.body, private_task.title
    assert_includes response.body, "Ação de origem ##{private_task.id}"
    assert_no_difference("ChecklistOccurrence.count") do
      post task_checklist_occurrences_path(@task), params: { checklist_occurrence: @attributes.merge(employee_id: other_employee.id) }
    end
    assert_response :not_found
  end

  test "DU AZ and HR can open the independent module from desktop and mobile navigation" do
    %i[du warehouse hr].each do |sector|
      @user.update!(role: :user, sector: sector)
      sign_in @user
      get checklist_occurrences_path
      assert_response :success
      assert_select "#navbarMain a[href=?]", checklist_occurrences_path, text: /Faltas de checklist/
      assert_select "#mobileNavOffcanvas a[href=?]", checklist_occurrences_path, text: /Faltas de checklist/
      assert_select "a.btn[href=?]", variaveis_path, text: "Início"
    end
  end

  test "area filters change totals ranking employee options and calendar while preserving navigation" do
    @employee.change_role!({ cargo: "motorista", sector: "du", promax: "FILTER-DU", starts_on: "2026-01-01", reason: "Admissão" }, user: @user)
    az = Employee.create!(nome: "Operador AZ", matricula: "FILTER-AZ")
    az.change_role!({ cargo: "operador", sector: "az", turno: 0, starts_on: "2026-01-01", reason: "Admissão" }, user: @user)
    @task.checklist_occurrences.create!(@attributes.merge(recorded_by: @user))
    @task.checklist_occurrences.create!(@attributes.merge(employee_id: az.id, checklist_kind: "empilhadeira", recorded_by: @user))
    get checklist_occurrences_path(year: 2026, employee_sector: "az")
    assert_response :success
    assert_select ".checklist-tracking__ranking tbody tr", count: 1
    assert_select ".checklist-tracking__ranking tbody td:first-child", text: /Operador AZ/
    assert_select "select[name=employee_id] option[value='#{@employee.id}']", count: 0
    assert_select ".checklist-tracking__total[data-action='click->checklist-occurrence-modal#open']"
    get checklist_occurrences_path(year: 2026, month: 3, employee_sector: "az", display: "calendar")
    assert_response :success
    assert_select ".checklist-tracking__ranking", count: 0
    assert_select ".checklist-tracking__calendar-day[data-calendar-date]", count: 31
    assert_select "[data-calendar-date='2026-03-14'] .checklist-tracking__day-count", text: /1/
    assert_select "[data-calendar-date='2026-03-14'] .checklist-tracking__day-people", text: /Operador AZ/
    assert_select ".checklist-tracking__calendar-navigation a[aria-label='Próximo mês']" do |links|
      query = Rack::Utils.parse_query(URI.parse(links.first["href"]).query)
      assert_equal "az", query["employee_sector"]
      assert_equal "4", query["month"]
    end
    get checklist_occurrences_path(year: 2026, employee_sector: "az", employee_id: @employee.id, display: "history")
    assert_response :success
    assert_select "#tracking-history-title", text: "Histórico"
  end

  test "calendar covers leap years and month navigation crosses year boundaries" do
    get checklist_occurrences_path(year: 2028, month: 2, display: "calendar")
    assert_response :success
    assert_select "[data-calendar-date='2028-02-29']"
    assert_select ".checklist-tracking__calendar-day[data-calendar-date]", count: 29
    get checklist_occurrences_path(year: 2026, month: 1, display: "calendar")
    assert_select ".checklist-tracking__calendar-navigation a[aria-label='Mês anterior']" do |links|
      query = Rack::Utils.parse_query(URI.parse(links.first["href"]).query)
      assert_equal "2025", query["year"]
      assert_equal "12", query["month"]
    end
  end

  test "history pagination preserves area and period filters" do
    @employee.change_role!({ cargo: "motorista", sector: "du", promax: "PAGE-DU", starts_on: "2026-01-01", reason: "Admissão" }, user: @user)
    21.times do |index|
      @task.checklist_occurrences.create!(@attributes.merge(occurred_on: Date.new(2026, 1, 1) + index.days, recorded_by: @user))
    end
    get checklist_occurrences_path(year: 2026, month: 1, employee_sector: "du", display: "history")
    assert_response :success
    assert_select "nav[aria-label='Páginas do histórico'] .checklist-tracking__page-link[aria-label='Próxima página']" do |links|
      query = Rack::Utils.parse_query(URI.parse(links.first["href"]).query)
      assert_equal "du", query["employee_sector"]
      assert_equal "1", query["month"]
      assert_equal "2", query["page"]
      assert_equal "history", query["display"]
    end
  end

  test "modal details show occurrences and exclusions update totals while retaining evidence" do
    label = @task.bucket.action_plan.labels.create!(name: "Matriz aplicada", color: "#27ae60")
    @task.labels << label
    record = @task.checklist_occurrences.create!(@attributes.merge(recorded_by: @user))
    get details_checklist_occurrences_path(year: 2026, month: 3, employee_id: @employee.id)
    assert_response :success
    assert_select "#checklistOccurrencesModal .checklist-tracking__modal-event", count: 1
    assert_select "[aria-label='Etiquetas da tarefa'] .task-label-badge", text: "Matriz aplicada"
    assert_select ".task-label-badge[style='--task-label-color: #27ae60']"
    assert_select "select[name='exclusion[reason]'] option[value=turned_map]", text: "Mapa virado"
    original_status = @task.completed
    patch exclude_checklist_occurrence_path(record), params: { exclusion: { reason: "network_error", details: "Sem conexão" } }, as: :json
    assert_response :success
    assert record.reload.cancelled_at?
    assert_equal "network_error", record.exclusion_category
    assert_equal original_status, @task.reload.completed
    get checklist_occurrences_path(year: 2026)
    assert_select ".checklist-tracking__ranking tbody tr", count: 0
    get checklist_occurrences_path(year: 2026, display: "history")
    assert_select ".checklist-tracking__history-actions a", text: "Desconsideradas (1)"
    assert_select ".checklist-tracking__candidate", count: 0
    get details_checklist_occurrences_path(year: 2026, employee_id: @employee.id, status: "excluded")
    assert_select ".checklist-tracking__modal-event.is-excluded", count: 1
    assert_select ".checklist-tracking__justification", text: /Erro de rede — Sem conexão/
  end

  test "exclusion requires justification for other reasons and respects employee sectors" do
    @employee.change_role!({ cargo: "operador", sector: "az", turno: 0, starts_on: "2026-01-01", reason: "Admissão" }, user: @user)
    record = @task.checklist_occurrences.create!(@attributes.merge(checklist_kind: "empilhadeira", recorded_by: @user))
    patch exclude_checklist_occurrence_path(record), params: { exclusion: { reason: "other", details: "" } }, as: :json
    assert_response :unprocessable_entity
    assert_nil record.reload.cancelled_at
    @user.update!(role: :user, sector: :du)
    sign_in @user
    patch exclude_checklist_occurrence_path(record), params: { exclusion: { reason: "execution_error" } }, as: :json
    assert_response :not_found
    sign_in @user
    get checklist_occurrences_path(employee_sector: "az")
    assert_response :forbidden
  end

  test "a team can justify its employee occurrence while private source details stay protected" do
    @employee.change_role!({ cargo: "motorista", sector: "du", promax: "PRIVATE-DU", starts_on: "2026-01-01", reason: "Admissão" }, user: @user)
    outsider = users(:two)
    outsider.update!(role: :user, sector: :warehouse)
    plan = outsider.action_plans.create!(name: "Plano de origem reservado", public: false, sector: :warehouse)
    task = plan.buckets.first.tasks.create!(title: "Detalhes privados da ação", creator: outsider)
    task.labels << plan.labels.create!(name: "Etiqueta privada da tarefa", color: "#ff0000")
    record = task.checklist_occurrences.create!(@attributes.merge(recorded_by: outsider))
    @user.update!(role: :user, sector: :du)
    sign_in @user
    get details_checklist_occurrences_path(year: 2026, employee_id: @employee.id)
    assert_response :success
    assert_select ".checklist-tracking__modal-event", count: 1
    assert_not_includes response.body, task.title
    assert_not_includes response.body, plan.name
    assert_not_includes response.body, "Etiqueta privada da tarefa"
    patch exclude_checklist_occurrence_path(record), params: { exclusion: { reason: "turned_map", details: "Mapa do dia anterior" } }, as: :json
    assert_response :success
    assert record.reload.cancelled_at?
    assert_equal @user, record.cancelled_by
  end

  test "navigation groups the module under DU AZ FROTA and RH and fleet access stays separate from HR" do
    get checklist_occurrences_path
    assert_select "#navbarMain .navbar-nav > a[href^='/ocorrencias-checklist']", count: 0
    assert_select "#duDropdown + ul a[href=?]", checklist_occurrences_path(employee_sector: "du"), text: "Faltas de checklist"
    assert_select "#azDropdown + ul a[href=?]", checklist_occurrences_path(employee_sector: "az"), text: "Faltas de checklist"
    assert_select "#rhDropdown + ul a[href=?]", checklist_occurrences_path, text: "Faltas de checklist"
    assert_select "ul[aria-labelledby=fleetDropdown] a[href=?]", checklist_occurrences_path, text: "Faltas de checklist"
    assert_select ".app-mobile-shortcuts a[href^='/ocorrencias-checklist']", count: 0
    assert_select "#mobileDuCollapse a[href=?]", checklist_occurrences_path(employee_sector: "du")
    assert_select "#mobileAzCollapse a[href=?]", checklist_occurrences_path(employee_sector: "az")
    assert_select "#mobileRhCollapse a[href=?]", checklist_occurrences_path
    assert_select "#mobileFleetCollapse a[href=?]", checklist_occurrences_path
    @user.update!(role: :user, sector: :fleet)
    sign_in @user
    assert_not @user.can_view_employees?
    get checklist_occurrences_path
    assert_response :success
    assert_select "ul[aria-labelledby=fleetDropdown] a[href=?]", checklist_occurrences_path
  end

  test "private plans and personal inboxes cannot be used to register occurrences" do
    outsider = users(:two)
    outsider.update!(role: :user, sector: :warehouse)
    private_plan = outsider.action_plans.create!(name: "Privado", sector: :warehouse, public: false)
    private_task = private_plan.buckets.first.tasks.create!(title: "Privada", creator: outsider)
    @user.update!(role: :user, sector: :du)
    get checklist_occurrences_path(action_plan_id: private_plan.id)
    assert_response :not_found
    sign_in @user
    post task_checklist_occurrences_path(private_task), params: { checklist_occurrence: @attributes }
    assert_response :not_found
    sign_in @user
    inbox_task = @user.personal_inbox!.tasks.create!(title: "Privada na entrada", creator: @user)
    post task_checklist_occurrences_path(inbox_task), params: { checklist_occurrence: @attributes }
    assert_response :forbidden
  end
end
