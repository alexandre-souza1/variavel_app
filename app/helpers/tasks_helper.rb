module TasksHelper
  def tasklist_path(task)
    action_plan_bucket_task_tasklist_path(task.bucket.action_plan, task.bucket, task)
  end
end
