class BucketsController < ApplicationController
  before_action :authenticate_user!

  def create
    @action_plan = editable_action_plans.find(params[:action_plan_id])

    @bucket = @action_plan.buckets.build(bucket_params)
    @bucket.position = @action_plan.buckets.count

    if @bucket.save
      redirect_to action_plan_path(@action_plan)
    else
      redirect_to action_plan_path(@action_plan), alert: "Erro ao criar bucket"
    end
  end

  def update
    @bucket = editable_buckets.find(params[:id])

    if @bucket.update(bucket_params)
      head :ok
    else
      head :unprocessable_entity
    end
  end

  def destroy
    @bucket = editable_buckets.find(params[:id])
    action_plan = @bucket.action_plan

    @bucket.destroy

    redirect_to action_plan_path(action_plan)
  end

  def done_tasks
    bucket = accessible_buckets.find(params[:id])
    @tasks = bucket.tasks
    .where(completed: true)
    .order(completed_at: :desc, due_at: :desc)

    render partial: "tasks/done_tasks", locals: { tasks: @tasks }
  end

  def toggle_complete
    @task.update!(completed: !@task.completed, completed_at: Time.current)
  end

private

  def accessible_action_plans
    return ActionPlan.all if current_user.admin?

    ActionPlan
      .left_joins(buckets: { tasks: :task_assignments })
      .where(
        "action_plans.user_id = :user_id
         OR tasks.creator_id = :user_id
         OR task_assignments.user_id = :user_id",
        user_id: current_user.id
      )
      .distinct
  end

  def editable_action_plans
    return ActionPlan.all if current_user.admin?

    current_user.action_plans
  end

  def accessible_buckets
    Bucket.where(action_plan_id: accessible_action_plans.select(:id))
  end

  def editable_buckets
    Bucket.where(action_plan_id: editable_action_plans.select(:id))
  end

  def bucket_params
    params.require(:bucket).permit(:name)
  end
end
