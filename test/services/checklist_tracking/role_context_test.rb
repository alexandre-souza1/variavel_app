require "test_helper"

class ChecklistTracking::RoleContextTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @task = tasks(:one)
    @task.update!(description: nil)
    @date = Date.new(2026, 5, 16)
    @operator = person("Rafael Operador Silva", "CTX-OP", "az", "operador")
    @az_helper = person("Rafael Ajudante Souza", "CTX-AZ", "az", "ajudante")
    @driver = person("Rafael Motorista Santos", "CTX-DR", "du", "motorista")
    @du_helper = person("Rafael Ajudante Oliveira", "CTX-DU", "du", "ajudante")
    @people = [@operator, @az_helper, @driver, @du_helper]
  end

  test "operator Rafael is disambiguated by role and AZ badge and receives forklift type" do
    title("operador Rafael")
    label("AZ")
    source = ChecklistTracking::TaskSource.new(@task)
    assert_equal @operator, source.suggested_employee(@people)
    assert_equal "empilhadeira", source.suggested_kind(@people)
    assert_equal({ employee_id: @operator.id, occurred_on: @date, checklist_kind: "empilhadeira" }, source.automatic_attributes(@people))
    result = ChecklistTracking::AutomaticRegistration.new(user: @user, tasks: Task.where(id: @task.id), year: 2026).call
    assert_equal 1, result.created
    assert_equal @operator, @task.checklist_occurrences.last.employee
  end

  test "AZ helper receives only pallet checklist and DU driver only departure or return" do
    title("colaborador Rafael", "de paleteira")
    label("Armazém")
    assert_equal @az_helper.id, source.automatic_attributes(@people)[:employee_id]
    @task.labels.clear
    title("motorista Rafael", "de retorno")
    label("DU")
    assert_equal @driver.id, source.automatic_attributes(@people)[:employee_id]
    assert_equal "retorno", source.automatic_attributes(@people)[:checklist_kind]
  end

  test "the role can fill a missing type for a unique full name but cannot choose departure versus return" do
    title("colaborador #{@az_helper.nome}")
    assert_equal "paleteira", source.automatic_attributes(@people)[:checklist_kind]
    title("motorista #{@driver.nome}")
    assert_nil source.automatic_attributes(@people)
    assert_match "tipo", source.review_reason(@people)
  end

  test "a badge can disambiguate a name but ambiguous coworkers and unknown roles remain for review" do
    title("colaborador Rafael", "de empilhadeira")
    label("AZ")
    other = person("Rafael Segundo Operador", "CTX-OP2", "az", "operador")
    assert_nil source.automatic_attributes(@people + [other])
    unknown = Employee.create!(nome: "Rafael Sem Histórico", matricula: "CTX-UNKNOWN")
    assert_nil source.automatic_attributes(@people + [unknown])
  end

  test "conflicting badges or a role inconsistent with the explicit person do not register" do
    title("operador #{@operator.nome}", "de empilhadeira")
    label("DU")
    assert_nil source.automatic_attributes(@people)
    assert_match "etiquetas", source.review_reason(@people)
    label("AZ")
    assert_nil source.automatic_attributes(@people)
    assert_match "DU e AZ", source.review_reason(@people)
    @task.labels.clear
    title("colaborador #{@az_helper.nome}", "de empilhadeira")
    assert_nil source.automatic_attributes(@people)
    assert_match "paleteira", source.review_reason(@people)
  end

  test "DU helpers cannot be registered even manually and restricted jobs reject other types" do
    [[@du_helper, "saida"], [@az_helper, "retorno"], [@operator, "paleteira"], [@driver, "empilhadeira"]].each do |employee, kind|
      record = ChecklistOccurrence.new(task: @task, employee: employee, recorded_by: @user, occurred_on: @date, checklist_kind: kind)
      assert_not record.valid?, "#{employee.nome}: #{kind}"
    end
    title("ajudante #{@du_helper.nome}", "de saída")
    assert_nil source.automatic_attributes(@people)
    assert_match "Ajudante DU não realiza", source.review_reason(@people)
  end

  test "historical roles exclude old DU helper records without deleting them after a promotion" do
    @du_helper.employee_roles.first.update!(ends_on: Date.new(2026, 6, 30))
    @du_helper.employee_roles.create!(cargo: "motorista", sector: "du", promax: "CTX-PROMOTED",
      starts_on: Date.new(2026, 7, 1), reason: "Promoção")
    @du_helper.employee_roles.reset
    old = @task.checklist_occurrences.new(employee: @du_helper, recorded_by: @user, occurred_on: @date, checklist_kind: "saida")
    old.save!(validate: false) # A record created before the role rule existed.
    current = @task.checklist_occurrences.create!(employee: @du_helper, recorded_by: @user,
      occurred_on: Date.new(2026, 8, 1), checklist_kind: "saida")
    report = ChecklistTracking::Report.new(scope: @task.checklist_occurrences, year: 2026)
    assert_equal 1, report.total
    assert_equal current.occurred_on, report.events.first[:date]
    history = ChecklistTracking::History.new(scope: @task.checklist_occurrences).events
    excluded = history.find { |event| event[:date] == @date }
    assert excluded[:excluded]
    assert_match "Ajudante DU", excluded[:role_restriction]
    assert ChecklistOccurrence.exists?(old.id)
    assert_nil old.reload.cancelled_at
    assert_equal 1, ChecklistTracking::History.new(scope: @task.checklist_occurrences).excluded_count
  end

  private

  def person(name, registration, sector, cargo)
    employee = Employee.create!(nome: name, matricula: registration)
    employee.employee_roles.create!(cargo: cargo, sector: sector, starts_on: Date.new(2026, 1, 1),
      promax: sector == "du" ? registration : nil, turno: sector == "az" ? 0 : nil, reason: "Admissão")
    employee
  end

  def title(person, kind = nil)
    @task.update!(title: "Aplicar matriz ao #{person} por não realização do Checklist #{kind} no dia 16/05/2026")
  end

  def label(name)
    @task.labels << @task.bucket.action_plan.labels.create!(name: name, color: "#ee7214")
  end

  def source
    ChecklistTracking::TaskSource.new(@task)
  end
end
