class LabelsController < ApplicationController
  before_action :authenticate_user!

  def create
    @label = Label.new(label_params)

    unless editable_action_plans.exists?(label_params[:action_plan_id])
      return render json: { errors: ["Action plan inválido"] }, status: :unprocessable_entity
    end

    if @label.save
      render json: @label
    else
      render json: { errors: @label.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def editable_action_plans
    return ActionPlan.all if current_user.admin?

    current_user.action_plans
  end

  def label_params
    params.require(:label).permit(:name, :color, :action_plan_id)
  end
end
