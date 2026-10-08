class TasksController < ApplicationController
  include MechanicTaskNavigation
  include TaskAccess
  before_action :authenticate_user!
  before_action :set_task, only: [:show, :update, :move, :toggle_complete]
  before_action :block_mechanical!, only: [:create]

  def create
    set_task_context
    @bucket = if params[:bucket_id].present?
      raise ActiveRecord::RecordNotFound unless @action_plan
      @action_plan.buckets.find(params[:bucket_id])
    else
      current_user.personal_inbox!
    end
    @task = @bucket.tasks.build(task_params.except(:bucket_id))

    @task.label_ids &= @bucket.action_plan&.label_ids || []
    @task.creator = current_user

    @task.position = 1

    if @task.save

      TaskActivityService.log(
        task: @task,
        user: current_user,
        activity_type: :created
      )
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to task_return_path }
      end
    else
      respond_to do |format|
        format.turbo_stream { render plain: @task.errors.full_messages.to_sentence, status: :unprocessable_entity }
        format.html do
          redirect_to task_return_path,
                      alert: @task.errors.full_messages.to_sentence
        end
      end
    end
  end

  def show
    render partial: "tasks/modal", locals: { task: @task }
  end

  def update
    old_due_at = @task.due_at
    old_bucket = @task.bucket
    old_users = @task.user_ids.sort
    @task.inbox_assignee_ids_before_move = old_users

    attributes = task_params
    if attributes[:bucket_id].present? && attributes[:bucket_id].to_i != @task.bucket_id
      destination = accessible_buckets.find(attributes[:bucket_id])
      head :forbidden and return unless allowed_destination?(destination)
      @task.broadcast_as_move = true
    end
    unless @task.update(attributes)
      render plain: @task.errors.full_messages.to_sentence, status: :unprocessable_entity
      return
    end

    if old_due_at != @task.due_at
      TaskActivityService.log(
        task: @task,
        user: current_user,
        activity_type: :due_date_changed,
        old_value: old_due_at,
        new_value: @task.due_at
      )
    end

    @bucket_changed = old_bucket.id != @task.bucket_id
    if @bucket_changed
      TaskActivityService.log(
        task: @task,
        user: current_user,
        activity_type: :bucket_changed,
        old_value: old_bucket.name,
        new_value: @task.bucket.name
      )
    end

    added_users = @task.user_ids - old_users

    if added_users.any?
      added_users.each do |user_id|

        added_user = User.find(user_id)

        TaskActivityService.log(
          task: @task,
          user: current_user,
          activity_type: :assignee_added,
          new_value: added_user.name,
          metadata: { user_id: added_user.id }
        )

      end
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to task_return_path }
    end
  end

  def move
    destination = params[:bucket_id].present? ? accessible_buckets.find(params[:bucket_id]) : @task.bucket
    head :forbidden and return unless allowed_destination?(destination)

    old_bucket = @task.bucket
    @task.inbox_assignee_ids_before_move = @task.user_ids
    @task.broadcast_as_move = true
    @task.update!(bucket: destination, position: destination_position(destination))

    if old_bucket.id != @task.bucket_id
      TaskActivityService.log(
        task: @task,
        user: current_user,
        activity_type: :bucket_changed,
        old_value: old_bucket.name,
        new_value: destination.name
      )
    end

    respond_to do |format|
      format.turbo_stream
      format.html { head :ok }
      format.json { head :ok }
    end
  rescue ActiveRecord::RecordInvalid => e
    render plain: e.record.errors.full_messages.to_sentence, status: :unprocessable_entity
  end

  def toggle_complete
    if params[:view] == "gerot_actions" && !@task.inbox?
      @gerot_source = @task.bucket.action_plan.routines.find(params[:routine_id]) if params[:routine_id].present?
    end
    new_status = !@task.completed

    @task.update!(
      completed: new_status,
      completed_at: new_status ? Time.current : nil
    )

    TaskActivityService.log(
      task: @task,
      user: current_user,
      activity_type: new_status ? :completed : :reopened
    )

    done_tasks = @task.bucket.tasks.visible_for(current_user).where(completed: true)
    if params[:view] == "gerot_actions" && !@task.inbox?
      done_tasks = done_tasks.where.not(routine_value_id: nil)
      done_tasks = done_tasks.joins(:routine_value).where(routine_values: { routine_id: @gerot_source.id }) if @gerot_source
    end
    @done_tasks_count = done_tasks.count

    @flash_container = new_status ? "Tarefa concluída" : "Tarefa reaberta"

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to task_return_path }
    end
  end

  private

  def set_task
    @task = find_accessible_task(params[:id])
  end

  def accessible_action_plans
    ActionPlan.visible_to(current_user)
  end

  def destination_position(destination)
    siblings = destination.tasks.visible_for(current_user).where.not(id: @task.id)
    if params[:view] == "gerot_actions" && !destination.inbox?
      siblings = siblings.where.not(routine_value_id: nil)
      if params[:routine_id].present?
        routine = destination.action_plan.routines.find(params[:routine_id])
        siblings = siblings.joins(:routine_value).where(routine_values: { routine_id: routine.id })
      end
    end

    following = if params[:following_task_id].present?
      siblings.find(params[:following_task_id])
    elsif params[:preceding_task_id].blank?
      matching_siblings = destination.inbox? ? siblings : siblings.where(completed: @task.completed?)
      matching_siblings.order(:position).offset([params[:position].to_i, 0].max).first
    end
    preceding = siblings.find(params[:preceding_task_id]) if !following && params[:preceding_task_id].present?
    unless following || preceding
      matching_siblings = destination.inbox? ? siblings : siblings.where(completed: @task.completed?)
      preceding = matching_siblings.order(:position).last
    end
    reference = following || preceding
    position = following ? following.position : preceding&.position.to_i + 1
    # acts_as_list removes the old position before inserting into the same list.
    position -= 1 if reference && destination == @task.bucket && @task.position < reference.position
    position
  end

  def accessible_buckets
    Bucket.where(action_plan_id: accessible_action_plans.select(:id))
      .or(Bucket.where(inbox: true, user_id: current_user.id))
  end

  def allowed_destination?(destination)
    return @task.creator_id == current_user.id && destination.user_id == current_user.id && @task.routine_value_id.nil? if destination.inbox?
    return false if @action_plan && destination.action_plan_id != @action_plan.id

    @task.inbox? || destination.action_plan_id == @task.bucket.action_plan_id
  end

  def block_mechanical!
    return unless current_user.mechanical?

    redirect_back(
      fallback_location: root_path,
      alert: "Você não possui permissão para realizar esta ação."
    )
  end

  def task_params
    params.require(:task).permit(
      :title, :description, :bucket_id,
      :start_at, :due_at,
      :comment, :assignee_id,
      :recurrence, :completed,
      :clone_tasklist_on_recurrence,
      :due_notification_enabled,
      label_ids: [], user_ids: [],
      tasklist_attributes: [
        :id, :title, :_destroy,
        tasklist_items_attributes: [:id, :content, :completed, :_destroy]
      ]
    ).tap do |whitelisted|

      # The reminder switch is submitted by a separate form that does not
      # contain labels or assignees. Do not turn omitted fields into empty
      # arrays, otherwise updating only the reminder removes existing links.
      if whitelisted.key?(:label_ids)
        whitelisted[:label_ids] = whitelisted[:label_ids].reject(&:blank?).map(&:to_i)
      end

      if whitelisted.key?(:user_ids)
        whitelisted[:user_ids] = whitelisted[:user_ids].reject(&:blank?).map(&:to_i)
      end

      if @task&.persisted? && whitelisted.key?(:label_ids)
        destination = whitelisted[:bucket_id].present? ? accessible_buckets.find(whitelisted[:bucket_id]) : @task.bucket
        whitelisted[:label_ids] &= destination.action_plan&.label_ids || []
      end

    end
  end

end
