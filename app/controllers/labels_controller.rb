class LabelsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_editable_action_plan, only: :destroy

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

  def destroy
    label = @action_plan.labels.find(params[:id])
    tasks_count = label.task_labels.count

    ActiveRecord::Base.transaction do
      TaskLabel.where(label_id: label.id).delete_all
      label.destroy!
    end

    message = if tasks_count.positive?
                "Label excluída e removida de #{tasks_count} tarefa(s)."
              else
                "Label excluída com sucesso."
              end

    redirect_to action_plan_path(@action_plan, view: "labels"), notice: message
  rescue ActiveRecord::RecordNotFound
    redirect_to action_plans_path, alert: "Label não encontrada."
  end

  private

  def editable_action_plans
    return ActionPlan.all if current_user.admin?

    current_user.action_plans
  end

  def set_editable_action_plan
    @action_plan = editable_action_plans.find(params[:action_plan_id])
  end

  def label_params
    params.require(:label).permit(:name, :color, :action_plan_id)
  end
end
