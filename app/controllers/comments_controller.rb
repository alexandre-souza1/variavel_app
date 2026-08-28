class CommentsController < ApplicationController
  before_action :authenticate_user!

  def create
    @task = accessible_tasks.find(params[:task_id])
    @comment = @task.comments.new(comment_params)
    @comment.user = current_user

    if @comment.save
      @task.broadcast_task_update
      respond_to do |format|
        format.turbo_stream { head :ok }
        format.html do
          destination = current_user.mechanical? ? mechanic_tasks_path : action_plan_path(@task.bucket.action_plan)
          redirect_to destination, notice: "Comentário adicionado."
        end
      end
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
    scope = Task.joins(:bucket).where(buckets: { action_plan_id: accessible_action_plans.select(:id) })
    current_user.mechanical? ? scope.visible_for(current_user) : scope
  end

  def comment_params
    params.require(:comment).permit(:content)
  end
end
