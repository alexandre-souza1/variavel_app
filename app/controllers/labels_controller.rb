class LabelsController < ApplicationController
  def create
    @label = Label.new(label_params)

    unless ActionPlan.exists?(label_params[:action_plan_id])
      return render json: { errors: ["Action plan inválido"] }, status: :unprocessable_entity
    end

    if @label.save
      render json: @label
    else
      render json: { errors: @label.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def label_params
    params.require(:label).permit(:name, :color, :action_plan_id)
  end
end