class ActionPlansController < ApplicationController
  before_action :set_action_plan, only: [:show]

  def index
    @action_plans = current_user.action_plans
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
    @action_plan = current_user.action_plans.find(params[:id])
    @buckets = @action_plan.buckets
    @bucket = Bucket.new
  end 

  def update
    @action_plan = current_user.action_plans.find(params[:id])
    
    if @action_plan.update(action_plan_params)
      redirect_to @action_plan, notice: "Plano atualizado com sucesso"
    else
      render :edit 
    end
  end

  def destroy
    @action_plan = current_user.action_plans.find(params[:id])
    @action_plan.destroy
    redirect_to action_plans_path, notice: "Plano excluído com sucesso"
  end

  private

  def set_action_plan
    @action_plan = current_user
      .action_plans
      .includes(buckets: :tasks)
      .find(params[:id])
  end

  def action_plan_params
    params.require(:action_plan).permit(:name, :description)
  end
end
