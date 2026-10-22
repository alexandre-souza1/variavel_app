require "test_helper"

class ChecklistTracking::TaskSourceTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @plan = tasks(:one).bucket.action_plan
    @bucket = tasks(:one).bucket
    @template = Routines::PlanTemplateBuilder.call(action_plan: @plan, attributes: { name: "Aderência GEROT" })
    @category = @template.routine_categories.find_by!(bucket: @bucket)
  end

  test "all four GEROT adherence formats identify the person type and reference date in one batch" do
    cases = [
      ["% Aderência Paleteira", "MARCELLO ALVES DA SILVA", "MARCELLO ALVES DA SILVA", "paleteira"],
      ["% Aderência Empilhadeira", "EVERTON FELIPE CARNIEL", "EVERTON FELIPE CARNIEL", "empilhadeira"],
      ["% Aderência Saída Rota", "PAULO EDSON", "PAULO EDSON DA SILVA", "saida"],
      ["% Aderência Retorno Rota", "IGOR DORIGON DA ROCHA", "IGOR DORIGON DA ROCHA", "retorno"]
    ]
    tasks = cases.each_with_index.map do |(indicator, comment, name, kind), index|
      person = Employee.create!(nome: name, matricula: "GEROT-#{index}")
      task = generated_task(indicator, comment)
      assert_equal "Investigar #{indicator} fora da meta — #{comment}", task.title
      assert_includes ChecklistTracking::TaskSource.candidates(Task.where(id: task.id)), task
      source = ChecklistTracking::TaskSource.new(task)
      assert_equal({ employee_id: person.id, occurred_on: task.routine_value.reference_date, checklist_kind: kind },
        source.automatic_attributes(Employee.includes(:employee_names).to_a))
      task
    end
    scope = Task.where(id: tasks.map(&:id))
    result = ChecklistTracking::AutomaticRegistration.new(user: @user, tasks: scope, year: 2026).call
    assert_equal 4, result.created
    assert_equal 0, result.pending
    assert_equal 4, ChecklistTracking::Report.new(scope: ChecklistOccurrence.where(task_id: scope.select(:id)), year: 2026).total
  end

  test "a unique shortened name in an old generated title also identifies the person" do
    person = Employee.create!(nome: "PAULO EDSON DA SILVA", matricula: "GEROT-SHORT")
    task = generated_task("% Aderência Saída Rota", "PAULO EDSON")
    task.update!(routine_comment: nil)
    assert_equal person.id, ChecklistTracking::TaskSource.new(task).automatic_attributes([person])[:employee_id]
  end

  test "ambiguous shortened names remain for review" do
    first = Employee.create!(nome: "PAULO EDSON DA SILVA", matricula: "GEROT-PAULO1")
    second = Employee.create!(nome: "PAULO EDSON DE SOUZA", matricula: "GEROT-PAULO2")
    task = generated_task("% Aderência Saída Rota", "PAULO EDSON")
    source = ChecklistTracking::TaskSource.new(task)
    assert_nil source.automatic_attributes([first, second])
    assert_equal :ambiguous, source.name_match([first, second]).confidence
  end

  test "names from later discussion do not override the GEROT origin comment" do
    person = Employee.create!(nome: "MARCELLO ALVES DA SILVA", matricula: "GEROT-ORIGIN")
    other = Employee.create!(nome: "Outra Pessoa da Discussão", matricula: "GEROT-LATER")
    task = generated_task("% Aderência Paleteira", person.nome)
    task.comments.create!(user: @user, content: "#{other.nome} vai conferir em 01/09/2026")
    attributes = ChecklistTracking::TaskSource.new(task).automatic_attributes([person, other])
    assert_equal person.id, attributes[:employee_id]
    assert_equal task.routine_value.reference_date, attributes[:occurred_on]
  end

  test "correcting the GEROT value does not hide an already generated missed checklist" do
    person = Employee.create!(nome: "MARCELLO ALVES DA SILVA", matricula: "GEROT-CORRECTED")
    task = generated_task("% Aderência Paleteira", person.nome)
    task.routine_value.update!(value: "100")
    assert_equal "paleteira", ChecklistTracking::TaskSource.new(task).automatic_attributes([person])[:checklist_kind]
  end

  test "availability productivity and short completion time are not assumed to be missing checklists" do
    person = Employee.create!(nome: "MARCELLO ALVES DA SILVA", matricula: "GEROT-OTHER")
    ["Disponibilidade Empilhadeiras", "% Aderência Produtividade", "Checklists Realizados < 1min (AZ)"].each do |name|
      task = generated_task(name, person.nome)
      assert_nil ChecklistTracking::TaskSource.new(task).automatic_attributes([person]), name
    end
  end

  test "conflicting types in a specific GEROT adherence indicator and comment need review" do
    person = Employee.create!(nome: "PAULO EDSON", matricula: "GEROT-CONFLICT")
    task = generated_task("% Aderência Saída Rota", "PAULO EDSON não fez checklist de retorno")
    source = ChecklistTracking::TaskSource.new(task)
    assert_nil source.automatic_attributes([person])
    assert_match "vários tipos", source.review_reason([person])
  end

  test "a copied adherence title without GEROT linkage is not automatically registered" do
    person = Employee.create!(nome: "MARCELLO ALVES DA SILVA", matricula: "GEROT-COPY")
    task = @bucket.tasks.create!(creator: @user, title: "Investigar % Aderência Paleteira fora da meta — #{person.nome}")
    assert_not_includes ChecklistTracking::TaskSource.candidates(Task.where(id: task.id)), task
    assert_nil ChecklistTracking::TaskSource.new(task).automatic_attributes([person])
  end

  private

  def generated_task(name, comment)
    indicator = @category.routine_indicators.create!(name: name, position: @category.routine_indicators.count,
      calculation_type: :ranged, value_type: :percentage, goal_direction: :greater_or_equal)
    indicator.routine_indicator_targets.create!(goal: "100", starts_at: Date.new(2026, 1, 1))
    if @routine
      @routine.update!(selected_indicator_ids: @routine.selected_indicator_ids + [indicator.id])
      @routine.ensure_expected_values!(indicators: [indicator])
    else
      @routine = Routines::Generator.call(template: @template, action_plan: @plan, created_by: @user,
        indicator_ids: [indicator.id], period_start: Date.new(2026, 8, 31), period_end: Date.new(2026, 8, 31))
    end
    value = @routine.routine_values.find_by!(routine_indicator: indicator)
    value.update!(value: "80")
    origin = value.routine_comments.create!(user: @user, body: comment)
    Routines::DeviationTaskGenerator.call(routine_value: value, actor: @user, comment: origin)
  end
end
