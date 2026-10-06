require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @task = tasks(:one)
    users(:one).update!(name: "User One")
    sign_in users(:one)
  end

  test "creates a task with bimonthly recurrence reminder and assignees" do
    assert_difference -> { Task.count }, 1 do
      post action_plan_bucket_tasks_url(@task.bucket.action_plan, @task.bucket),
           params: { task: { title: "Inspeção bimestral", due_at: "2027-02-28", recurrence: "bimonthly",
                             due_notification_enabled: "1", user_ids: [users(:one).id] } },
           as: :turbo_stream
    end

    assert_response :success
    created = Task.order(:id).last
    assert_equal "bimonthly", created.recurrence
    assert created.due_notification_enabled?
    assert_equal Date.new(2027, 2, 28), created.due_at.to_date
    assert_equal [users(:one).id], created.user_ids
    assert_select "#task_#{created.id} .bi-bell"
    assert_select "#task_#{created.id} .bi-arrow-repeat"
  end

  test "toggling the reminder preserves existing assignees and label badges" do
    assert_equal [users(:one).id], @task.user_ids
    assert_equal [labels(:one).id], @task.label_ids

    [true, false].each do |enabled|
      patch action_plan_bucket_task_url(@task.bucket.action_plan, @task.bucket, @task),
            params: { task: { due_notification_enabled: enabled } },
            as: :turbo_stream

      assert_response :success
      assert_equal [users(:one).id], @task.reload.user_ids
      assert_equal [labels(:one).id], @task.label_ids
      assert_equal enabled, @task.due_notification_enabled?
      assert_select "#task_#{@task.id} .task-labels .badge", text: labels(:one).name
    end
  end

  test "new tasks persist multiple selected badges and ignore labels from other plans" do
    extra = @task.bucket.action_plan.labels.create!(name: "Prioridade", color: "#3616b6")
    assert_difference -> { Task.count }, 1 do
      post action_plan_bucket_tasks_url(@task.bucket.action_plan, @task.bucket),
        params: { task: { title: "Nova tarefa com etiquetas", due_notification_enabled: "0",
          label_ids: ["", labels(:one).id, extra.id, labels(:two).id] } }, as: :turbo_stream
    end
    assert_response :success
    created = Task.order(:id).last
    assert_equal [labels(:one).id, extra.id].sort, created.label_ids.sort
    assert_not created.due_notification_enabled?
    assert_select "#task_#{created.id} .task-label-badge", count: 2
  end

  test "explicit label updates filter labels from other plans and allow clearing" do
    patch action_plan_bucket_task_url(@task.bucket.action_plan, @task.bucket, @task),
          params: { task: { label_ids: ["", labels(:one).id.to_s, labels(:two).id.to_s] } },
          as: :turbo_stream

    assert_response :success
    assert_equal [labels(:one).id], @task.reload.label_ids

    patch action_plan_bucket_task_url(@task.bucket.action_plan, @task.bucket, @task),
          params: { task: { label_ids: [""] } },
          as: :turbo_stream

    assert_response :success
    assert_empty @task.reload.label_ids
  end

  test "completing a bimonthly task renders the next occurrence" do
    @task.update!(due_at: Time.zone.local(2026, 12, 31, 10), completed: false)

    patch action_plan_bucket_task_url(@task.bucket.action_plan, @task.bucket, @task),
          params: { task: { recurrence: "bimonthly" } },
          as: :turbo_stream

    assert_response :success
    assert_equal "bimonthly", @task.reload.recurrence

    assert_difference -> { Task.count }, 1 do
      patch toggle_complete_action_plan_bucket_task_url(@task.bucket.action_plan, @task.bucket, @task),
            as: :turbo_stream
    end

    assert_response :success
    next_task = Task.find_by!(bucket: @task.bucket, title: @task.title, due_at: Time.zone.local(2027, 2, 28, 10))
    assert_select "turbo-stream[action='prepend'][target='open-tasks-#{@task.bucket_id}'] template #task_#{next_task.id}"
  end

  test "updates multiple checklist items pasted into the task form" do
    tasklist = @task.tasklist
    initial_count = tasklist.tasklist_items.count

    patch action_plan_bucket_task_url(@task.bucket.action_plan, @task.bucket, @task),
          params: {
            task: {
              tasklist_attributes: {
                id: tasklist.id,
                tasklist_items_attributes: {
                  "0" => { content: "Primeiro item colado", completed: "0", _destroy: "false" },
                  "1" => { content: "Segundo item colado", completed: "0", _destroy: "false" }
                }
              }
            }
          },
          as: :turbo_stream

    assert_response :success
    assert_equal initial_count + 2, tasklist.reload.tasklist_items.count
    assert_equal ["Primeiro item colado", "Segundo item colado"],
                 tasklist.tasklist_items.order(:id).last(2).pluck(:content)
  end
end
