class ActionPlansController < ApplicationController
  before_action :authenticate_user!
  before_action :set_action_plan, only: [:show, :assign_open_tasks]
  before_action :set_owned_action_plan, only: [:edit, :update, :destroy]

  def index
    # Planos que o usuário pode acessar
    @action_plans = accessible_action_plans

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

    @task_to_open = Task.find_by(id: params[:task_id])

    # Usuários disponíveis para receber as tarefas
    @users = User.order(:name)
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
    @action_plan = ActionPlan.new
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
    @action_plan.destroy

    redirect_to action_plans_path,
                notice: "Plano excluído com sucesso"
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

  def action_plan_params
    params.require(:action_plan).permit(:name, :description)
  end
end
