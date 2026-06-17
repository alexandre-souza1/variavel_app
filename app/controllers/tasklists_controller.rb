class TasklistsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_task
  before_action :set_tasklist, only: [:destroy, :update]

  def create
    @tasklist = @task.create_tasklist!(title: "Checklist")

    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, notice: "Checklist criado com sucesso" }
      format.turbo_stream {
        render turbo_stream: turbo_stream.replace("task_checklist", partial: "tasks/checklist", locals: { task: @task })
      }
    end
  end

  def destroy
    @tasklist.destroy

    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, notice: "Checklist removido" }
      format.turbo_stream {
        render turbo_stream: turbo_stream.remove("checklist_container")
      }
    end
  end

  def update
    if @tasklist.update(tasklist_params)
      respond_to do |format|
        format.html { redirect_back fallback_location: root_path, notice: "Checklist atualizado" }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace("task_checklist", partial: "tasks/checklist", locals: { task: @task })
        }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_task
    @task = accessible_tasks.find(params[:task_id])
  end

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

  def set_tasklist
    @tasklist = @task.tasklist
    redirect_back fallback_location: root_path, alert: "Checklist não encontrado" unless @tasklist
  end

  def tasklist_params
    params.require(:tasklist).permit(:title)
  end
end
