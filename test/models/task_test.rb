require "test_helper"

class TaskTest < ActiveSupport::TestCase
  setup do
    users(:one).update!(name: "User One")
  end

  test "bimonthly recurrence advances two calendar months and handles shorter months" do
    [
      [Time.zone.local(2026, 7, 15, 10), Time.zone.local(2026, 9, 15, 10)],
      [Time.zone.local(2026, 12, 31, 10), Time.zone.local(2027, 2, 28, 10)],
      [Time.zone.local(2027, 12, 31, 10), Time.zone.local(2028, 2, 29, 10)]
    ].each do |due_at, expected_due_at|
      task = tasks(:one)
      task.update!(due_at: due_at, recurrence: "bimonthly", completed: false)

      assert_difference -> { Task.count }, 1 do
        task.update!(completed: true)
      end

      next_task = Task.find_by!(bucket: task.bucket, title: task.title, due_at: expected_due_at)
      assert_equal "bimonthly", next_task.recurrence
      assert_not next_task.completed?
    end
  end

  test "clones the checklist as pending items when a recurring task is completed" do
    task = tasks(:one)
    task.update!(
      title: "Tarefa recorrente com checklist",
      due_at: 1.day.from_now,
      recurrence: "daily",
      clone_tasklist_on_recurrence: true,
      completed: false
    )
    task.tasklist.tasklist_items.update_all(completed: false)
    task.tasklist.tasklist_items.create!(content: "Conferir equipamento", completed: true)

    assert_difference -> { Task.count }, 1 do
      task.update!(completed: true)
    end

    next_task = Task.find_by!(bucket: task.bucket, title: task.title, due_at: task.due_at + 1.day)
    assert_equal ["MyString", "Conferir equipamento"].sort,
                 next_task.tasklist.tasklist_items.pluck(:content).sort
    assert next_task.tasklist.tasklist_items.none?(&:completed?)
    assert next_task.clone_tasklist_on_recurrence?
  end

  test "does not clone the checklist when the option is disabled" do
    task = tasks(:one)
    task.update!(
      title: "Tarefa recorrente sem checklist",
      due_at: 1.day.from_now,
      recurrence: "daily",
      clone_tasklist_on_recurrence: false,
      completed: false
    )
    task.tasklist.tasklist_items.create!(content: "Não copiar", completed: false)

    assert_difference -> { Task.count }, 1 do
      task.update!(completed: true)
    end

    next_task = Task.find_by!(bucket: task.bucket, title: task.title, due_at: task.due_at + 1.day)
    assert_empty next_task.tasklist.tasklist_items
  end
end
