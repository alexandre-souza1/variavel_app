class CommentsController < ApplicationController
  include MechanicTaskNavigation
  include TaskAccess
  before_action :authenticate_user!

  def create
    @task = find_accessible_task(params[:task_id])
    @comment = @task.comments.new(comment_params)
    @comment.user = current_user

    if @comment.save
      @task.broadcast_task_update
      respond_to do |format|
        format.turbo_stream { head :ok }
        format.html do
          destination = task_return_path
          redirect_to destination, notice: "Comentário adicionado."
        end
      end
    else
      head :unprocessable_entity
    end
  end

  private

  def comment_params
    params.require(:comment).permit(:content)
  end
end
