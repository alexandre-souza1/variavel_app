module TasksHelper
  def tasklist_path(task)
    task_tasklist_path(task)
  end

  def task_bucket_options(task)
    inbox = current_user.personal_inbox!
    inbox_option = task.creator_id == current_user.id && task.routine_value_id.nil? ? [["Entrada pessoal", inbox.id]] : []
    plans = if @action_plan
      [@action_plan]
    elsif task.inbox?
      ActionPlan.visible_to(current_user).includes(:buckets).order(:name)
    else
      [task.bucket.action_plan]
    end
    groups = plans.map { |plan| [plan.name, plan.buckets.work.map { |bucket| [bucket.name, bucket.id] }] }
    options_for_select(inbox_option, task.bucket_id) + grouped_options_for_select(groups, task.bucket_id)
  end
end
