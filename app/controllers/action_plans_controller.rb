class ActionPlansController < ApplicationController
  before_action :authenticate_user!
  before_action :set_action_plan, only: [:show, :assign_open_tasks, :export_excel]
  before_action :require_admin!, only: :assign_open_tasks
  before_action :set_owned_action_plan, only: [:edit, :update, :destroy]

  def toggle_hidden
    @action_plan = accessible_action_plans.find(params[:id])
    hidden_action_plan = current_user.hidden_action_plans.find_by(action_plan: @action_plan)

    if hidden_action_plan
      hidden_action_plan.destroy!
      notice = "Plano exibido novamente."
    else
      current_user.hidden_action_plans.create!(action_plan: @action_plan)
      notice = "Plano ocultado da sua lista."
    end

    redirect_back fallback_location: action_plans_path, notice: notice
  end

  def inbox_preference
    collapsed = ActiveModel::Type::Boolean.new.cast(params[:collapsed])
    current_user.update!(action_plan_inbox_collapsed: collapsed)
    head :no_content
  end

  def index
    # Planos que o usuário pode acessar
    @action_plans = accessible_action_plans
    @hidden_action_plan_ids = current_user.hidden_action_plans.pluck(:action_plan_id)
    @show_hidden_action_plans = params[:show_hidden] == "1"
    @action_plans = @action_plans.where.not(id: @hidden_action_plan_ids) unless @show_hidden_action_plans

    # Busca continua funcionando
    if params[:query].present?
      q = "%#{params[:query]}%"

      @action_plans = @action_plans
        .left_joins(buckets: :tasks)
        .left_joins(buckets: { tasks: :users })
        .where(
          "action_plans.name ILIKE :q
           OR action_plans.description ILIKE :q
           OR tasks.title ILIKE :q
           OR users.name ILIKE :q",
          q: q
        )
        .distinct
    end

    # Mantém carregamento eficiente
    @action_plans = @action_plans.order(:name)

    # -------------------------
    # DASHBOARD PESSOAL
    # -------------------------

    @my_tasks = Task
      .joins(:bucket).where(buckets: { inbox: false })
      .joins(:task_assignments)
      .includes(bucket: :action_plan)
      .where(task_assignments: { user_id: current_user.id })
      .where(completed: false)
      .order(
        Arel.sql(
          "CASE WHEN due_at IS NULL THEN 1 ELSE 0 END, due_at ASC"
        )
      )

    @calendar_tasks = @my_tasks.where.not(due_at: nil)
    @today_tasks = @my_tasks.where(due_at: Date.current.all_day)
    @overdue_tasks = @my_tasks.where("due_at < ?", Time.current)

    @calendar_start_date =
      if params[:start_date].present?
        Date.parse(params[:start_date]) rescue Date.today
      else
        Date.today
      end
  end

  def show
    @buckets = @action_plan
      .buckets
      .includes(tasks: :users)
      .order(:position)

    @inbox_bucket = current_user.personal_inbox!

    @work_buckets = @buckets.reject(&:inbox?)
    @inbox_tasks = @inbox_bucket&.tasks
      &.visible_for(current_user)
      &.includes(:users, :labels)
      &.order(:position) || Task.none

    visible_tasks = Task
      .joins(:bucket)
      .where(buckets: { action_plan_id: @action_plan.id })
      .visible_for(current_user)

    @open_tasks_count = visible_tasks
      .where(completed: [false, nil])
      .count

    @done_tasks_count = visible_tasks
      .where(completed: true)
      .count

    @overdue_tasks_count = visible_tasks
      .where(completed: [false, nil])
      .where.not(due_at: nil)
      .where("due_at < ?", Time.current)
      .count

    @task_to_open = visible_tasks.or(Task.joins(:bucket).where(bucket: @inbox_bucket, creator: current_user).visible_for(current_user)).find_by(id: params[:task_id])

    # Usuários disponíveis para receber as tarefas
    @users = User.order(:name)
    @labels = @action_plan.labels.includes(:tasks).order(:name)
    @can_manage_labels = current_user.admin? || @action_plan.user_id == current_user.id
    if params[:view] == "dashboard"
      @dashboard = ActionPlans::Dashboard.new(action_plan: @action_plan, user: current_user, source: params[:source])
      @dashboard_filters = params.permit(:status, :bucket_id, :member_id).to_h
      filtered = @dashboard.filtered_tasks(**@dashboard_filters.symbolize_keys)
      @dashboard_task_count = filtered.count
      @dashboard_page = params[:page].to_i.clamp(1, [(@dashboard_task_count / 10.0).ceil, 1].max)
      @dashboard_tasks = filtered.limit(10).offset((@dashboard_page - 1) * 10)
    end
    if params[:view] == "gerot_actions"
      @source_gerots = @action_plan.routines.order(period_start: :desc)
      @source_gerot = @source_gerots.find(params[:routine_id]) if params[:routine_id].present?
      sources = @source_gerot ? @action_plan.routines.where(id: @source_gerot.id) : @source_gerots
      @generated_tasks = Task.where(routine_value_id: sources.joins(:routine_values).select("routine_values.id"))
        .visible_for(current_user).includes(:bucket, :users, :labels).order(created_at: :desc)
    end
    if params[:view] == "gerots"
      @can_manage_gerots = @action_plan.manageable_by?(current_user)
      @gerot_year = @action_plan.gerot_year
      year_start = Date.new(@gerot_year, 1, 1)
      @plan_gerots = @action_plan.routines
        .where("period_start <= ? AND period_end >= ?", year_start.end_of_year, year_start)
        .includes(:routine_template).order(period_start: :desc)
      @gerot_tasks = Task.where(routine_value_id: @action_plan.routines.joins(:routine_values).select("routine_values.id"))
        .visible_for(current_user)
      @gerot_template = @action_plan.gerot_template
      @available_templates = @gerot_template&.active? ? [@gerot_template] : []
      @unlinked_gerots = Routine.visible_to(current_user).where(action_plan_id: nil)
        .joins(:routine_template).where(routine_templates: { sector: @action_plan.sector }).order(period_start: :desc)
      @unlinked_gerots = @unlinked_gerots.where(created_by: current_user) unless current_user.admin?
    end
  end

  def export_excel
    respond_to do |format|
      format.xlsx do
        response.headers["Content-Disposition"] =
          %(attachment; filename="plano_de_acao_#{@action_plan.id}.xlsx")
      end
      format.any { head :not_acceptable }
    end
  end

  def assign_open_tasks
    user_ids = Array(params[:user_ids])
      .reject(&:blank?)
      .map(&:to_i)
      .uniq

    if user_ids.empty?
      redirect_to action_plan_path(
        @action_plan,
        view: params[:view]
      ), alert: "Selecione pelo menos um responsável."
      return
    end

    users = User.where(id: user_ids)

    if users.empty?
      redirect_to action_plan_path(
        @action_plan,
        view: params[:view]
      ), alert: "Nenhum usuário válido foi selecionado."
      return
    end

    open_tasks = Task
      .joins(:bucket)
      .where(
        buckets: { action_plan_id: @action_plan.id },
        completed: [false, nil]
      )

    assigned_count = 0

    ActiveRecord::Base.transaction do
      open_tasks.find_each do |task|
        # Remove os responsáveis atuais
        task.task_assignments.destroy_all

        # Adiciona todos os usuários selecionados
        users.each do |user|
          task.task_assignments.create!(
            user_id: user.id
          )
        end

        assigned_count += 1
      end
    end

    user_names = users
      .pluck(:name)
      .join(", ")

    redirect_to action_plan_path(
      @action_plan,
      view: params[:view]
    ),
      notice: "#{assigned_count} tarefa(s) aberta(s) atribuída(s) para: #{user_names}."

  rescue ActiveRecord::RecordInvalid => e
    redirect_to action_plan_path(
      @action_plan,
      view: params[:view]
    ),
      alert: "Não foi possível atribuir as tarefas: #{e.message}"
  end

  def new
    @action_plan = ActionPlan.new(sector: current_user.sector)
  end

  def create
    @action_plan = current_user.action_plans.build(action_plan_params)

    if @action_plan.save
      redirect_to @action_plan, notice: "Plano criado com sucesso"
    else
      render :new
    end
  end

  def edit
    @buckets = @action_plan.buckets
    @bucket = Bucket.new
  end

  def update
    if @action_plan.update(action_plan_params)
      redirect_to @action_plan, notice: "Plano atualizado com sucesso"
    else
      render :edit
    end
  end

  def destroy
    if @action_plan.destroy
      redirect_to action_plans_path, notice: "Plano excluído com sucesso"
    else
      redirect_to action_plan_path(@action_plan, view: "gerots"),
                  alert: "Este plano possui GEROTs vinculados e não pode ser excluído."
    end
  end

  def sort_buckets
    @action_plan = current_user.admin? ?
      ActionPlan.find(params[:id]) :
      current_user.action_plans.find(params[:id])

    params[:bucket_ids].each_with_index do |id, index|
      @action_plan.buckets
                .where(id: id)
                .update_all(position: index)
    end
    Routines::PlanTemplateSynchronizer.call(action_plan: @action_plan)

    head :ok
  end

  private

  def set_action_plan
    @action_plan = accessible_action_plans
      .includes(buckets: :tasks)
      .find(params[:id])
  end

  def set_owned_action_plan
    @action_plan =
      if current_user.admin?
        ActionPlan.find(params[:id])
      else
        current_user.action_plans.find(params[:id])
      end
  end

  def accessible_action_plans
    ActionPlan.visible_to(current_user)
  end

  def action_plan_params
    permitted = [:name, :description, :public]
    permitted << :sector if current_user.admin?

    params.require(:action_plan).permit(permitted)
  end
end
