class TasklistItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_task
  before_action :set_item, only: :update

  def create
    @tasklist = @task.tasklist || @task.build_tasklist
    @item = @tasklist.tasklist_items.build(tasklist_item_params)
    @item.content = "Novo item" if @item.content.blank?
    @item.completed = false if @item.completed.nil?

    if @item.save
      @task.broadcast_task_update
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.append(
            "tasklist-items-#{@task.id}",
            partial: "tasklist_items/item",
            locals: { item: @item, task: @task }
          )
        end
        format.html do
          destination = current_user.mechanical? ? mechanic_tasks_path : action_plan_path(@task.bucket.action_plan)
          redirect_to destination, notice: "Item adicionado à lista."
        end
        format.json { render json: { id: @item.id }, status: :created }
      end
    else
      head :unprocessable_entity
    end
  end

  def update
    if @item.update(tasklist_item_params)
      @task.broadcast_task_update
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "tasklist-item-#{@item.id}",
            partial: "tasklist_items/item",
            locals: { item: @item, task: @task }
          )
        end
        format.html do
          destination = current_user.mechanical? ? mechanic_tasks_path : action_plan_path(@task.bucket.action_plan)
          redirect_to destination, notice: "Item atualizado."
        end
      end
    else
      head :unprocessable_entity
    end
  end

  private

  def set_task
    @task = accessible_tasks.find(params[:task_id])
  end

  def accessible_tasks
    scope = Task.joins(:bucket).where(buckets: { action_plan_id: accessible_action_plans.select(:id) })
    current_user.mechanical? ? scope.visible_for(current_user) : scope
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

  def tasklist_item_params
    params.fetch(:tasklist_item, {}).permit(:content, :completed)
  end

  def set_item
    @item = @task.tasklist.tasklist_items.find(params[:id])
  end
end
