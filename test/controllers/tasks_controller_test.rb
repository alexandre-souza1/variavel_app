require "test_helper"

class TasksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @task = tasks(:one)
    users(:one).update!(name: "User One")
    sign_in users(:one)
  end

  test "updating the reminder preserves existing assignees" do
    assert_equal [users(:one).id], @task.user_ids

    patch action_plan_bucket_task_url(@task.bucket.action_plan, @task.bucket, @task),
          params: { task: { due_notification_enabled: true } },
          as: :turbo_stream

    assert_response :success
    assert_equal [users(:one).id], @task.reload.user_ids
    assert @task.due_notification_enabled?
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
