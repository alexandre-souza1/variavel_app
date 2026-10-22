require "test_helper"

class ChecklistTracking::SpotTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @task = tasks(:one)
    @task.update!(title: "Aplicar matriz ao SPOT IZI3B97 por não realização do Checklist de Saída no dia 29/04/2026", description: nil)
    @task.labels << @task.bucket.action_plan.labels.create!(name: "SPOT", color: "#ee7214")
  end

  test "manual SPOT text identifies plate date and type without an employee or fleet registration" do
    source = ChecklistTracking::TaskSource.new(@task)
    assert source.spot?
    assert_equal({ spot_plate: "IZI3B97", occurred_on: Date.new(2026, 4, 29), checklist_kind: "saida" }, source.automatic_attributes([]))
    assert_no_difference(["Employee.count", "Plate.count"]) do
      result = identify
      assert_equal 1, result.created
    end
    assert_nil @task.checklist_occurrences.last.employee_id
    assert_equal "SPOT IZI3B97", @task.checklist_occurrences.last.subject_name
  end

  test "GEROT SPOT adherence means departure and uses the cell date with a plate only comment" do
    task = gerot_task("DLL4A97")
    source = ChecklistTracking::TaskSource.new(task)
    assert_equal "Investigar % Aderência SPOT fora da meta — DLL4A97", task.title
    assert_includes ChecklistTracking::TaskSource.candidates(Task.where(id: task.id)), task
    assert_equal({ spot_plate: "DLL4A97", occurred_on: task.routine_value.reference_date, checklist_kind: "saida" }, source.automatic_attributes([]))
    result = identify(tasks: Task.where(id: [@task.id, task.id]))
    assert_equal 2, result.created
    assert_equal 2, report.total
    assert_equal %w[DLL4A97 IZI3B97], report.rows.map { |row| row[:spot_plate] }.sort
  end

  test "two sources for the same plate date and kind count once and different plates stay separate" do
    task = gerot_task("IZI3B97")
    identify(tasks: Task.where(id: [@task.id, task.id]))
    assert_equal 1, report.total
    assert_equal 2, report.events.first[:sources].size
    other = @task.bucket.tasks.create!(title: "Outra placa", creator: @user)
    other.checklist_occurrences.create!(spot_plate: "DLL4A97", occurred_on: "2026-04-29", checklist_kind: "saida", recorded_by: @user)
    assert_equal 2, report.total
    assert_equal 2, report.rows.size
    @task.update!(completed: true)
    assert_equal 2, report.total
  end

  test "SPOT badge supports a plate without SPOT in the title and normalizes old plate format" do
    @task.update!(title: "Não realização do Checklist de Saída ABC-1234 no dia 29/04/2026")
    assert_equal "ABC1234", ChecklistTracking::TaskSource.new(@task).automatic_attributes([])[:spot_plate]
    record = @task.checklist_occurrences.create!(spot_plate: "izi-3b97", occurred_on: "2026-04-29", checklist_kind: "saida", recorded_by: @user)
    assert_equal "IZI3B97", record.spot_plate
  end

  test "multiple plates missing dates or conflicting GEROT kinds need review" do
    @task.update!(title: "SPOT IZI3B97 e DLL4A97 não realizaram checklist de saída em 29/04/2026")
    assert_nil ChecklistTracking::TaskSource.new(@task).automatic_attributes([])
    @task.update!(title: "SPOT IZI3B97 não realizou checklist de saída")
    assert_nil ChecklistTracking::TaskSource.new(@task).automatic_attributes([])
    task = gerot_task("DLL4A97 não realizou checklist de retorno")
    assert_nil ChecklistTracking::TaskSource.new(task).automatic_attributes([])
  end

  test "employee and SPOT batches are separate and existing records are preserved" do
    assert_equal 0, ChecklistTracking::AutomaticRegistration.new(user: @user, tasks: Task.where(id: @task.id), year: 2026).call.created
    assert_equal 1, identify.created
    assert_equal 1, identify.preserved
    assert_equal 0, identify(year: 2025).created
    employee = Employee.create!(nome: "Pessoa Teste", matricula: "SPOT-PERSON")
    invalid = @task.checklist_occurrences.new(employee: employee, spot_plate: "DLL4A97", occurred_on: "2026-04-29", checklist_kind: "saida", recorded_by: @user)
    assert_not invalid.valid?
  end

  test "justifying one plate preserves other plates and kinds and late duplicates inherit the reason" do
    identify
    record = @task.checklist_occurrences.last
    duplicate_task = @task.bucket.tasks.create!(title: "Outra fonte", creator: @user)
    duplicate = duplicate_task.checklist_occurrences.create!(record.attributes.slice("spot_plate", "occurred_on", "checklist_kind", "recorded_by_id"))
    other = duplicate_task.checklist_occurrences.create!(spot_plate: "DLL4A97", occurred_on: record.occurred_on, checklist_kind: "saida", recorded_by: @user)
    retorno = duplicate_task.checklist_occurrences.create!(spot_plate: record.spot_plate, occurred_on: record.occurred_on, checklist_kind: "retorno", recorded_by: @user)
    assert_equal 2, ChecklistTracking::Exclusion.new(occurrence: record, user: @user, reason: "network_error", details: "Sem conexão").call
    assert duplicate.reload.cancelled_at?
    assert_nil other.reload.cancelled_at
    assert_nil retorno.reload.cancelled_at
    assert_equal 2, report.total
    later_task = @task.bucket.tasks.create!(title: "Nova fonte", creator: @user)
    later = later_task.checklist_occurrences.create!(record.attributes.slice("spot_plate", "occurred_on", "checklist_kind", "recorded_by_id"))
    assert later.cancelled_at?
    assert_equal "Erro de rede — Sem conexão", later.cancellation_reason
  end

  test "SPOT visibility and inherited justifications respect access to private source tasks" do
    @user.update!(role: :user, sector: :fleet)
    outsider = users(:two)
    outsider.update!(role: :user, sector: :warehouse)
    plan = outsider.action_plans.create!(name: "SPOT privado", public: false, sector: :warehouse)
    task = plan.buckets.first.tasks.create!(title: "Fonte privada SPOT", creator: outsider)
    hidden = task.checklist_occurrences.create!(spot_plate: "IZI3B97", occurred_on: "2026-04-29", checklist_kind: "saida", recorded_by: outsider)
    hidden.update!(cancelled_at: Time.current, cancelled_by: outsider, cancellation_reason: "Justificativa privada", exclusion_category: "other")
    assert_not ChecklistOccurrence.visible_to(@user).exists?(hidden.id)
    identify
    visible = @task.checklist_occurrences.last
    assert_nil visible.cancelled_at
    ChecklistTracking::Exclusion.new(occurrence: visible, user: @user, reason: "turned_map", details: nil).call
    assert_equal "Justificativa privada", hidden.reload.cancellation_reason
  end

  private

  def identify(tasks: Task.where(id: @task.id), year: 2026)
    ChecklistTracking::AutomaticRegistration.new(user: @user, tasks: tasks, year: year, subject: "spot").call
  end

  def report
    ChecklistTracking::Report.new(scope: ChecklistOccurrence.spots, year: 2026)
  end

  def gerot_task(comment)
    plan = @task.bucket.action_plan
    template = Routines::PlanTemplateBuilder.call(action_plan: plan, attributes: { name: "Checklist SPOT" })
    category = template.routine_categories.find_by!(bucket: @task.bucket)
    indicator = category.routine_indicators.create!(name: "% Aderência SPOT", position: 0, calculation_type: :ranged, value_type: :percentage)
    indicator.routine_indicator_targets.create!(goal: "100", starts_at: "2026-01-01")
    routine = Routines::Generator.call(template: template, action_plan: plan, created_by: @user,
      period_start: Date.new(2026, 4, 29), period_end: Date.new(2026, 4, 29))
    value = routine.routine_values.find_by!(routine_indicator: indicator)
    value.update!(value: "80")
    origin = value.routine_comments.create!(user: @user, body: comment)
    Routines::DeviationTaskGenerator.call(routine_value: value, actor: @user, comment: origin)
  end
end
