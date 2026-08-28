class MechanicTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mechanical!

  def index
    @status = params[:status].presence_in(%w[open completed all]) || "open"
    all_tasks = current_user.tasks
      .includes(:labels, :comments, tasklist: :tasklist_items, bucket: :action_plan)
      .order(Arel.sql("completed ASC, CASE WHEN due_at IS NULL THEN 1 ELSE 0 END, due_at ASC"))

    @tasks = case @status
             when "completed" then all_tasks.where(completed: true)
             when "all" then all_tasks
             else all_tasks.where(completed: [false, nil])
             end

    @open_count = all_tasks.where(completed: [false, nil]).count
    @completed_count = all_tasks.where(completed: true).count
    @total_count = @open_count + @completed_count
  end

  private

  def require_mechanical!
    return if current_user.mechanical?

    redirect_to root_path, alert: "Acesso restrito aos mecânicos."
  end
end
