class MechanicTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mechanical!

  def index
    @status = params[:status].presence_in(%w[open completed all]) || "open"
    @view = params[:view].presence_in(%w[kanban list]) || "kanban"
    @query = params[:q].to_s.strip
    @label_ids = Array(params[:label_ids]).filter_map { |id| Integer(id.to_s, exception: false)&.to_s }.uniq
    @filter_params = {
      status: @status, view: @view, q: @query.presence,
      action_plan_id: params[:action_plan_id].presence, label_ids: @label_ids
    }.compact
    @filters_active = @query.present? || @label_ids.any? || params[:action_plan_id].present?

    @action_plans = ActionPlan
      .joins(buckets: { tasks: :task_assignments })
      .where(task_assignments: { user_id: current_user.id })
      .distinct
      .order(:name)

    assigned_task_ids = TaskAssignment
      .where(user_id: current_user.id)
      .select(:task_id)

    assigned_tasks = Task.joins(:bucket).where(buckets: { inbox: false }).where(id: assigned_task_ids)
    @labels = Label.where(id: TaskLabel.where(task_id: assigned_task_ids).select(:label_id))
      .includes(:action_plan).order(:name, :id)
    all_tasks = assigned_tasks

    if params[:action_plan_id].present?
      all_tasks = all_tasks
        .joins(:bucket)
        .where(buckets: { action_plan_id: params[:action_plan_id] })
    end

    if @query.present?
      title_pattern = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      all_tasks = all_tasks.where("tasks.title ILIKE ?", title_pattern)
    end

    if @label_ids.any?
      all_tasks = all_tasks.where(id: TaskLabel.where(label_id: @label_ids).select(:task_id))
    end

    @open_count = all_tasks
      .where(tasks: { completed: [false, nil] })
      .count

    @completed_count = all_tasks
      .where(tasks: { completed: true })
      .count

    @total_count = @open_count + @completed_count
    @overdue_count = all_tasks.where(completed: [false, nil]).where("tasks.due_at < ?", Time.current).count

    @tasks =
      case @status
      when "completed"
        all_tasks.where(tasks: { completed: true })

      when "all"
        all_tasks

      else
        all_tasks.where(tasks: { completed: [false, nil] })
      end

    @tasks = @tasks.includes(
      :labels, comments: :user, tasklist: :tasklist_items, bucket: :action_plan
    ).order(
      Arel.sql(
        <<~SQL.squish
          tasks.completed ASC,
          CASE
            WHEN tasks.due_at IS NULL THEN 1
            ELSE 0
          END,
          tasks.due_at ASC,
          tasks.id ASC
        SQL
      )
    )

    if @view == "kanban"
      @task_positions = @tasks.each_with_index.to_h { |task, position| [task.id, position] }
      @tasks_by_bucket = @tasks.group_by(&:bucket)
        .sort_by { |bucket, _| [bucket.action_plan.name.downcase, bucket.action_plan_id, bucket.position || 0, bucket.id] }
    end
  end

  private

  def require_mechanical!
    return if current_user.mechanical?

    redirect_to root_path, alert: "Acesso restrito aos mecânicos."
  end
end
