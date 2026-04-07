class ActionPlansController < ApplicationController
  before_action :set_action_plan, only: [:show]

  def index
    @action_plans = current_user.action_plans
  end

  def show
    @buckets = @action_plan.buckets.includes(:tasks)
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

  private

  def set_action_plan
    @action_plan = current_user.action_plans.find(params[:id])
  end

  def action_plan_params
    params.require(:action_plan).permit(:name, :description)
  end
end
