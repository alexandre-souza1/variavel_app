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
end
