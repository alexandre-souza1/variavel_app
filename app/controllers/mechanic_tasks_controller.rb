class MechanicTasksController < ApplicationController
  before_action :authenticate_user!
  before_action :require_mechanical!

  def index
    @status = params[:status].presence_in(%w[open completed all]) || "open"

    # Planos de ação que possuem tarefas atribuídas ao mecânico atual
    @action_plans = ActionPlan
      .joins(buckets: :tasks)
      .where(tasks: { user_id: current_user.id })
      .distinct
      .order(:name)

    # Todas as tarefas do mecânico
    all_tasks = current_user.tasks
      .includes(
        :labels,
        :comments,
        tasklist: :tasklist_items,
        bucket: :action_plan
      )

    # Filtro por plano de ação
    if params[:action_plan_id].present?
      all_tasks = all_tasks
        .joins(bucket: :action_plan)
        .where(action_plans: { id: params[:action_plan_id] })
    end

    # Ordenação
    all_tasks = all_tasks.order(
      Arel.sql(
        "completed ASC,
         CASE WHEN due_at IS NULL THEN 1 ELSE 0 END,
         due_at ASC"
      )
    )

    # Filtro de status
    @tasks = case @status
             when "completed"
               all_tasks.where(completed: true)
             when "all"
               all_tasks
             else
               all_tasks.where(completed: [false, nil])
             end

    # Resumo sempre respeitando o plano selecionado
    @open_count = all_tasks.where(completed: [false, nil]).count
    @completed_count = all_tasks.where(completed: true).count
    @total_count = @open_count + @completed_count
  end

  private

  def require_mechanical!
    return if current_user.mechanical?

    redirect_to root_path, alert: "Acesso restrito aos mecânicos."
  end
end
