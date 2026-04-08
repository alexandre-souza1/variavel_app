class CommentsController < ApplicationController
  def create
    @task = Task.find(params[:task_id])
    @comment = @task.comments.new(comment_params)
    @comment.user = current_user

    if @comment.save
      head :ok
    else
      redirect_to action_plan_task_path(params[:action_plan_id], @task), alert: "Erro ao comentar"
    end
  end

  private

  def comment_params
    params.require(:comment).permit(:content)
  end
end