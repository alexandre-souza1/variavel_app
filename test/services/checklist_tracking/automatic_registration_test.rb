require "test_helper"

class ChecklistTracking::AutomaticRegistrationTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @person = Employee.create!(nome: "ALEXANDRE LOPEZ", matricula: "AUTO-01")
    @task = tasks(:one)
    @task.update!(title: "Aplicar matriz ao motorista ALEXANDRE LOPEZ por não realização do Checklist de Retorno no dia 31/08/2026", description: nil)
  end

  test "registers clear names dates and types once with an audit trail" do
    assert_difference(["ChecklistOccurrence.count", "TaskActivity.count"], 1) { assert_equal 1, identify.created }
    occurrence = @task.checklist_occurrences.last
    assert_equal @person, occurrence.employee
    assert_equal Date.new(2026, 8, 31), occurrence.occurred_on
    assert_equal "retorno", occurrence.checklist_kind
    assert_equal "automatic_name", TaskActivity.last.metadata["identification_method"]
    assert_no_difference(["ChecklistOccurrence.count", "TaskActivity.count"]) { assert_equal 0, identify.created }
  end

  test "does not derive the absence date from creation or a later discussion" do
    @task.update!(title: "Aplicar matriz ao motorista ALEXANDRE LOPEZ por não realização do Checklist de Retorno")
    @task.comments.create!(user: @user, content: "Cobrar o retorno em 31/08/2026")
    assert_equal 0, identify.created
    assert_equal 1, identify.pending
  end

  test "different dates or types in the same action need review" do
    @task.update!(title: @task.title + " e 01/09/2026")
    assert_equal 0, identify.created
    @task.update!(title: "ALEXANDRE LOPEZ não realizou checklist de saída e retorno em 31/08/2026")
    assert_equal 0, identify.created
  end

  test "a later comment about another person or date does not change the explicit source" do
    other = Employee.create!(nome: "Pessoa de Cobrança", matricula: "AUTO-02")
    @task.comments.create!(user: @user, content: "Pessoa de Cobrança vai verificar o checklist de saída em 01/09/2026")
    assert_equal 1, identify.created
    assert_equal @person, @task.checklist_occurrences.last.employee
    assert_equal Date.new(2026, 8, 31), @task.checklist_occurrences.last.occurred_on
  end

  test "the GEROT comment supplies the specific type instead of the generic indicator title" do
    plan = @task.bucket.action_plan
    template = Routines::PlanTemplateBuilder.call(action_plan: plan, attributes: { name: "Modelo checklist" })
    category = template.routine_categories.find_by!(bucket: @task.bucket)
    indicator = category.routine_indicators.create!(name: "Checklist de segurança realizado", position: 0,
      calculation_type: :ranged, value_type: :percentage)
    routine = Routines::Generator.call(template: template, action_plan: plan, created_by: @user,
      period_start: Date.new(2026, 8, 1), period_end: Date.new(2026, 8, 31))
    value = routine.routine_values.where(routine_indicator: indicator).first
    comment = value.routine_comments.create!(user: @user,
      body: "Aplicar matriz ao motorista ALEXANDRE LOPEZ por não realização do checklist de retorno")
    @task.update!(routine_value: value, routine_comment: comment,
      title: "Investigar Checklist de segurança realizado fora da meta — #{comment.body}")
    assert_equal 1, identify.created
    occurrence = @task.checklist_occurrences.last
    assert_equal "retorno", occurrence.checklist_kind
    assert_equal value.reference_date, occurrence.occurred_on
  end

  test "existing manual registrations and cancellations are never overwritten" do
    occurrence = @task.checklist_occurrences.create!(employee: @person, occurred_on: "2026-08-31", checklist_kind: "retorno", recorded_by: @user)
    occurrence.update!(cancelled_at: Time.current, cancelled_by: @user, cancellation_reason: "Não foi uma falta")
    assert_no_difference("ChecklistOccurrence.count") do
      result = identify
      assert_equal 0, result.created
      assert_equal 1, result.preserved
    end
    assert occurrence.reload.cancelled_at?
  end

  test "respects the selected year and task visibility" do
    assert_equal 0, identify(year: 2025).created
    outsider = users(:two)
    outsider.update!(role: :user, sector: :warehouse)
    @user.update!(role: :user, sector: :safety)
    plan = outsider.action_plans.create!(name: "Private", public: false, sector: :warehouse)
    private_task = plan.buckets.first.tasks.create!(title: @task.title, creator: outsider)
    assert_equal 0, identify(tasks: Task.where(id: private_task.id)).created
  end

  private

  def identify(year: 2026, tasks: Task.where(id: @task.id))
    ChecklistTracking::AutomaticRegistration.new(user: @user, tasks: tasks, year: year).call
  end
end
