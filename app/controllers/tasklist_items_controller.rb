class TasklistItemsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_task

  def create
    @tasklist = @task.tasklist || @task.build_tasklist
    @item = @tasklist.tasklist_items.build(content: "Novo item", completed: false)

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
        format.json { render json: { id: @item.id }, status: :created }
      end
    else
      head :unprocessable_entity
    end
  end

  private

  def set_task
    @task = Task.find(params[:task_id])
  end
end
