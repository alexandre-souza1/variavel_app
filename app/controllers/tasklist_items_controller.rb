class TasklistItemsController < ApplicationController
  include MechanicTaskNavigation
  include TaskAccess
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
          destination = task_return_path
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
          destination = task_return_path
          redirect_to destination, notice: "Item atualizado."
        end
      end
    else
      head :unprocessable_entity
    end
  end

  private

  def set_task
    @task = find_accessible_task(params[:task_id])
  end

  def tasklist_item_params
    params.fetch(:tasklist_item, {}).permit(:content, :completed)
  end

  def set_item
    @item = @task.tasklist.tasklist_items.find(params[:id])
  end
end
