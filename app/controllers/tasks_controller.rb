class TasksController < ApplicationController
  before_action :authenticate_user!
  before_action :set_task, only: [:show, :update, :move, :toggle_complete]

  def create
    @bucket = accessible_buckets.find(params[:bucket_id])
    @task = @bucket.tasks.build(task_params)

    @task.label_ids &= @bucket.action_plan.label_ids
    @task.creator = current_user

    # Desloca todas as tarefas para baixo
    @bucket.tasks.update_all("position = position + 1")
    @task.position = 0

    if @task.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to action_plan_path(@bucket.action_plan) }
      end
    else
      respond_to do |format|
        format.turbo_stream
        format.html do
          redirect_to action_plan_path(@bucket.action_plan),
                      alert: @task.errors.full_messages.to_sentence
        end
      end
    end
  end

  def show
    render partial: "tasks/modal", locals: { task: @task }
  end

  def update
    @task = Task.find(params[:id])
    @task.update(task_params)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to action_plan_path(@task.bucket.action_plan) }
    end
  end

  def move
    new_bucket_id = params[:bucket_id]
    new_position = params[:position].to_i

    if new_bucket_id.present? && new_bucket_id.to_i != @task.bucket_id
      new_bucket = accessible_buckets.find(new_bucket_id)
      head :forbidden and return unless new_bucket.action_plan_id == @task.bucket.action_plan_id

      @task.update!(bucket: new_bucket)
    end

    @task.insert_at(new_position + 1)

    head :ok
  end

  def toggle_complete
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

  def set_task
    @task = accessible_tasks.find(params[:id])
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

  def accessible_buckets
    Bucket.where(action_plan_id: accessible_action_plans.select(:id))
  end

  def accessible_tasks
    Task.where(bucket_id: accessible_buckets.select(:id))
  end

  def task_params
    params.require(:task).permit(
      :title, :description,
      :start_at, :due_at,
      :comment, :assignee_id,
      :recurrence, :completed,
      label_ids: [], user_ids: [],
      tasklist_attributes: [
        :id, :title, :_destroy,
        tasklist_items_attributes: [:id, :content, :completed, :_destroy]
      ]
    ).tap do |whitelisted|

      whitelisted[:label_ids] = whitelisted[:label_ids]&.reject(&:blank?) || []
      whitelisted[:user_ids]  = whitelisted[:user_ids]&.reject(&:blank?) || []

      whitelisted[:label_ids] = whitelisted[:label_ids].map(&:to_i)
      whitelisted[:user_ids]  = whitelisted[:user_ids].map(&:to_i)

      if @task&.persisted?
        whitelisted[:label_ids] &= @task.bucket.action_plan.label_ids
      end

    end
  end

end
