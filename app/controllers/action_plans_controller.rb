class ActionPlansController < ApplicationController
  before_action :authenticate_user!
  before_action :set_action_plan, only: [:show]
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



    # mantém carregamento eficiente
    @action_plans = @action_plans
      .includes(buckets: { tasks: :users })



    # -------------------------
    # DASHBOARD PESSOAL
    # -------------------------


    @my_tasks = Task
      .joins(:task_assignments)
      .where(task_assignments: { user_id: current_user.id })
      .where(completed: false)
      .order(Arel.sql("CASE WHEN due_at IS NULL THEN 1 ELSE 0 END, due_at ASC"))

    @calendar_tasks = @my_tasks.where.not(due_at: nil)
    @today_tasks = @my_tasks.where(due_at: Date.current.all_day)

    @calendar_start_date =
      if params[:start_date].present?
        Date.parse(params[:start_date]) rescue Date.today
      else
        Date.today
      end

  end

  def show
    @buckets = @action_plan.buckets
    @buckets = @action_plan.buckets.order(:name)
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
    redirect_to action_plans_path, notice: "Plano excluído com sucesso"
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
