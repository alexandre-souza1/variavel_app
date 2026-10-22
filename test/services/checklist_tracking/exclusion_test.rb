require "test_helper"

class ChecklistTracking::ExclusionTest < ActiveSupport::TestCase
  setup do
    @person = Employee.create!(nome: "Pessoa Justificada", matricula: "JUST-01")
    @user = users(:one)
    @task = tasks(:one)
    @record = @task.checklist_occurrences.create!(employee: @person, recorded_by: @user,
      occurred_on: "2026-03-14", checklist_kind: "saida")
  end

  test "justifies every action for one absence and preserves other dates and types" do
    duplicate_task = @task.bucket.tasks.create!(title: "Outra investigação", creator: @user)
    duplicate = duplicate_task.checklist_occurrences.create!(@record.attributes.slice("employee_id", "recorded_by_id", "occurred_on", "checklist_kind"))
    other_type = @task.checklist_occurrences.create!(employee: @person, recorded_by: @user, occurred_on: @record.occurred_on, checklist_kind: "retorno")
    other_day = @task.checklist_occurrences.create!(employee: @person, recorded_by: @user, occurred_on: @record.occurred_on + 1.day, checklist_kind: "saida")
    assert_difference("TaskActivity.count", 2) { assert_equal 2, exclude(reason: "network_error", details: "Sem sinal no pátio") }
    [@record, duplicate].each do |record|
      assert record.reload.cancelled_at?
      assert_equal "network_error", record.exclusion_category
      assert_equal "Erro de rede — Sem sinal no pátio", record.cancellation_reason
      assert_equal @user, record.cancelled_by
    end
    assert_nil other_type.reload.cancelled_at
    assert_nil other_day.reload.cancelled_at
    assert_equal 2, ChecklistTracking::Report.new(scope: ChecklistOccurrence.all, year: 2026).total
    assert_no_difference("TaskActivity.count") { assert_equal 0, exclude(reason: "turned_map", details: nil) }
    assert_equal "network_error", @record.reload.exclusion_category
  end

  test "a later action about the same justified absence remains excluded" do
    exclude(reason: "turned_map", details: "Execução ficou no mapa anterior")
    later_task = @task.bucket.tasks.create!(title: "Cobrança duplicada", creator: @user)
    later = later_task.checklist_occurrences.create!(employee: @person, recorded_by: @user,
      occurred_on: @record.occurred_on, checklist_kind: @record.checklist_kind)
    assert later.cancelled_at?
    assert_equal "turned_map", later.exclusion_category
    assert_equal @record.reload.cancellation_reason, later.cancellation_reason
    assert_equal 0, ChecklistTracking::Report.new(scope: ChecklistOccurrence.all, year: 2026).total
  end

  test "other reasons require a justification and unknown reasons are rejected" do
    assert_raises(ChecklistTracking::Exclusion::InvalidChange) { exclude(reason: "other", details: "  ") }
    assert_raises(ChecklistTracking::Exclusion::InvalidChange) { exclude(reason: "invalid", details: "Teste") }
    assert_nil @record.reload.cancelled_at
    assert_equal 1, exclude(reason: "other", details: "Checklist feito no equipamento reserva")
  end

  private

  def exclude(reason:, details:)
    ChecklistTracking::Exclusion.new(occurrence: @record, user: @user, reason: reason, details: details).call
  end
end
