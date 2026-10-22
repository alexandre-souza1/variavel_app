require "test_helper"

class ChecklistTracking::ReportTest < ActiveSupport::TestCase
  setup do
    @employee = Employee.create!(nome: "José da Silva", matricula: "TRACK-01")
    @user = users(:one)
    @task = tasks(:one)
  end

  test "counts the year of the absence and deduplicates actions without merging different types" do
    create_occurrence(@task, Date.new(2025, 12, 31), "saida")
    first = create_occurrence(@task, Date.new(2026, 1, 10), "saida")
    second_task = @task.bucket.tasks.create!(title: "Outra ação sobre a falta", creator: @user, completed: true)
    create_occurrence(second_task, first.occurred_on, "saida")
    create_occurrence(@task, first.occurred_on, "retorno")
    create_occurrence(@task, Date.new(2026, 2, 10), "saida")
    create_occurrence(@task, Date.new(2027, 1, 1), "saida")

    report = report_for(2026)
    assert_equal 3, report.total
    assert_equal [2, 1] + [0] * 10, report.monthly_counts
    assert_equal 1, report.recurring_count
    assert_equal 3, report.pending_count
    assert_equal 2, report.events.find { |event| event[:date] == first.occurred_on && event[:kind] == "Saída" }[:sources].size
    @task.update!(completed: true)
    assert_equal 3, report_for(2026).total
    assert_equal 0, report_for(2026).pending_count
  end

  test "cancellation preserves evidence and allows a corrected registration" do
    record = create_occurrence(@task, Date.new(2026, 3, 1), "saida")
    duplicate = record.dup
    assert_not duplicate.valid?
    record.update!(cancelled_at: Time.current, cancelled_by: @user, cancellation_reason: "Data incorreta")
    assert_equal 0, report_for(2026).total
    assert ChecklistOccurrence.exists?(record.id)
    create_occurrence(@task, Date.new(2026, 3, 1), "saida")
    assert_equal 1, report_for(2026).total
  end

  test "tracked tasks cannot return to a private inbox" do
    create_occurrence(@task, Date.new(2026, 3, 1), "saida")
    @task.bucket = @task.creator.personal_inbox!
    assert_not @task.valid?
  end

  test "suggestions normalize names and leave ambiguous names unselected" do
    @task.update!(title: "Aplicar matriz ao motorista JOSE por não realização do Checklist de Saída no dia 10/01/2025", description: nil)
    source = ChecklistTracking::TaskSource.new(@task)
    assert_equal @employee, source.suggested_employee([@employee])
    assert_equal Date.new(2025, 1, 10), source.suggested_date
    assert_equal "saida", source.suggested_kind
    other = Employee.create!(nome: "José de Oliveira", matricula: "TRACK-02")
    assert_nil source.suggested_employee([@employee, other])
  end

  test "suggestions use task comments and do not use the assignee as the employee" do
    @task.update!(title: "Checklist não realizado", description: nil)
    @task.comments.create!(user: @user, content: "José da Silva: checklist de retorno em 15/04/2026")
    source = ChecklistTracking::TaskSource.new(@task)
    assert_equal @employee, source.suggested_employee([@employee])
    assert_equal Date.new(2026, 4, 15), source.suggested_date
    assert_equal "retorno", source.suggested_kind
    assert_equal 0, ChecklistOccurrence.count
  end

  test "recurring farol messages do not enter the candidate queue" do
    @task.update!(title: "Envio de Farol de Checklist no Grupo DU e AZ", description: "Os motoristas não realizaram o checklist")
    assert_not_includes ChecklistTracking::TaskSource.candidates(Task.all).pluck(:id), @task.id
  end

  private

  def create_occurrence(task, date, kind)
    task.checklist_occurrences.create!(employee: @employee, recorded_by: @user, occurred_on: date, checklist_kind: kind)
  end

  def report_for(year)
    ChecklistTracking::Report.new(scope: ChecklistOccurrence.all, year: year)
  end
end
