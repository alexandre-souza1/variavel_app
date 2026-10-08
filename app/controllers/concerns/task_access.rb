module TaskAccess
  extend ActiveSupport::Concern

  private

  def accessible_tasks
    Task.accessible_to(current_user)
  end

  def set_task_context
    @action_plan = ActionPlan.visible_to(current_user).find(params[:action_plan_id]) if params[:action_plan_id].present?
  end

  def find_accessible_task(id)
    set_task_context
    task = accessible_tasks.find(id)
    if params[:bucket_id].present? && action_name != "move"
      raise ActiveRecord::RecordNotFound unless task.bucket_id == params[:bucket_id].to_i
    end
    if @action_plan && !task.inbox? && task.bucket.action_plan_id != @action_plan.id
      raise ActiveRecord::RecordNotFound
    end
    @action_plan ||= task.bucket.action_plan
    task
  end

  def task_return_path
    return mechanic_tasks_return_path if current_user.mechanical? && !@task.inbox?
    return action_plan_path(@action_plan, view: params[:view].presence) if @action_plan

    inbox_path
  end
end
