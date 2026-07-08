class CommentsController < ApplicationController
  before_action :authenticate_user!

  def create
    @task = accessible_tasks.find(params[:task_id])
    @comment = @task.comments.new(comment_params)
    @comment.user = current_user

    if @comment.save
      head :ok
    else
      head :unprocessable_entity
    end
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

  def accessible_tasks
    Task.joins(:bucket).where(buckets: { action_plan_id: accessible_action_plans.select(:id) })
  end

  def comment_params
    params.require(:comment).permit(:content)
  end
end
