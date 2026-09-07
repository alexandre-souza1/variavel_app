class MechanicTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mechanical!

  def index
    @status = params[:status].presence_in(%w[open completed all]) || "open"

    @action_plans = ActionPlan
      .joins(buckets: { tasks: :task_assignments })
      .where(task_assignments: { user_id: current_user.id })
      .distinct
      .order(:name)

    assigned_task_ids = TaskAssignment
      .where(user_id: current_user.id)
      .select(:task_id)

    all_tasks = Task
      .where(id: assigned_task_ids)
      .includes(
        :labels,
        :comments,
        tasklist: :tasklist_items,
        bucket: :action_plan
      )

    if params[:action_plan_id].present?
      all_tasks = all_tasks
        .joins(:bucket)
        .where(buckets: { action_plan_id: params[:action_plan_id] })
    end

    @open_count = all_tasks
      .where(tasks: { completed: [false, nil] })
      .count

    @completed_count = all_tasks
      .where(tasks: { completed: true })
      .count

    @total_count = @open_count + @completed_count

    @tasks =
      case @status
      when "completed"
        all_tasks.where(tasks: { completed: true })

      when "all"
        all_tasks

      else
        all_tasks.where(tasks: { completed: [false, nil] })
      end

    @tasks = @tasks.order(
      Arel.sql(
        <<~SQL.squish
          tasks.completed ASC,
          CASE
            WHEN tasks.due_at IS NULL THEN 1
            ELSE 0
          END,
          tasks.due_at ASC
        SQL
      )
    )
  end

  private

  def require_mechanical!
    return if current_user.mechanical?

    redirect_to root_path, alert: "Acesso restrito aos mecânicos."
  end
end
