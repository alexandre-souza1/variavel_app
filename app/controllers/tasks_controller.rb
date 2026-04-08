class TasksController < ApplicationController

  def create
    @bucket = Bucket.find(params[:bucket_id])
    @task = @bucket.tasks.build(task_params)
    @task.creator = current_user
    @task.position = @bucket.tasks.count

    if @task.save
      redirect_to action_plan_path(@bucket.action_plan)
    else
      redirect_to action_plan_path(@bucket.action_plan), alert: "Erro ao criar tarefa"
    end
  end

  def show
    @task = Task.find(params[:id])
    render partial: "tasks/modal", locals: { task: @task }
  end

  def update
    @task = Task.find(params[:id])

    if @task.update(task_params)
      redirect_to action_plan_path(@task.bucket.action_plan)
    else
      redirect_to action_plan_path(@task.bucket.action_plan), alert: "Erro ao atualizar"
    end
  end

  def move
    @task = Task.find(params[:id])

    @task.update(
      bucket_id: params[:bucket_id],
      position: params[:position]
    )

    head :ok
  end

  private

  def task_params
    params.require(:task).permit(
      :title,
      :description,
      :start_at,
      :due_at,
      :comment,
      :assignee_id
    )
  end
end
