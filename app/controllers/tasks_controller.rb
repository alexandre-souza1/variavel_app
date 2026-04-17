class TasksController < ApplicationController

  def create
    @bucket = Bucket.find(params[:bucket_id])
    @task = @bucket.tasks.build(task_params)
    @task.creator = current_user
    @task.position = @bucket.tasks.count

    if @task.save
      redirect_to action_plan_path(@bucket.action_plan)
    else
      redirect_to action_plan_path(@bucket.action_plan), alert: @task.errors.full_messages.to_sentence
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

    new_bucket_id = params[:bucket_id]
    new_position = params[:position].to_i

    if new_bucket_id.present? && new_bucket_id.to_i != @task.bucket_id
      @task.update!(bucket_id: new_bucket_id)
    end

    @task.insert_at(new_position + 1)

    head :ok
  end

  def toggle_complete
    @task = Task.find(params[:id])

    new_status = !@task.completed

    @task.update!(
      completed: new_status,
      completed_at: new_status ? Time.current : nil
    )

    @flash_container = new_status ? "Tarefa concluída" : "Tarefa reaberta"

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to action_plan_path(@task.bucket.action_plan) }
    end
  end

  private

  def task_params
    params.require(:task).permit(
      :title, :description,
      :start_at, :due_at,
      :comment, :assignee_id,
      :recurrence, :completed, :bucket_id,
      label_ids: [], user_ids: [],
      tasklist_attributes: [
        :id, :title, :_destroy,
        tasklist_items_attributes: [:id, :content, :completed, :_destroy]
      ]
    ).tap do |whitelisted|
      whitelisted[:label_ids] = whitelisted[:label_ids]&.reject(&:blank?) || []
      whitelisted[:user_ids]  = whitelisted[:user_ids]&.reject(&:blank?) || []
    end
  end

end
