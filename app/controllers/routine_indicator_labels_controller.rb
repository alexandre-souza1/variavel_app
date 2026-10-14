class RoutineIndicatorLabelsController < ApplicationController
  before_action :authenticate_user!

  def update
    routine = Routine.visible_to(current_user).find(params[:routine_id])
    template = routine.routine_template
    return head :forbidden unless template.action_plan && template.manageable_by?(current_user)

    indicator = RoutineIndicator.joins(:routine_category)
      .where(routine_categories: { routine_template_id: template.id })
      .where(id: routine.selected_indicator_ids).find(params[:id])

    if indicator.update(params.require(:routine_indicator).permit(label_ids: []))
      redirect_to routine, notice: "Etiquetas do indicador atualizadas.", status: :see_other
    else
      redirect_to routine, alert: indicator.errors.full_messages.to_sentence, status: :see_other
    end
  rescue ActiveRecord::RecordInvalid => error
    redirect_to routine, alert: error.record.errors.full_messages.to_sentence, status: :see_other
  end
end
