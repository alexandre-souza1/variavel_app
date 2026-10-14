class RoutineIndicatorLabelsController < ApplicationController
  before_action :authenticate_user!

  def update
    routine = Routine.visible_to(current_user).find(params[:routine_id])
    template = routine.routine_template
    unless template.action_plan && template.manageable_by?(current_user)
      return render_error(routine, params[:id], "Você não tem permissão para alterar as etiquetas deste indicador.", status: :forbidden)
    end

    indicator = RoutineIndicator.joins(:routine_category)
      .where(routine_categories: { routine_template_id: template.id })
      .where(id: routine.selected_indicator_ids).find(params[:id])

    if indicator.update(params.require(:routine_indicator).permit(label_ids: []))
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.update("routine-indicator-labels-#{routine.id}-#{indicator.id}",
              partial: "routine_indicators/labels", locals: { indicator: indicator, compact: true }),
            turbo_stream.update("routine-indicator-labels-status-#{routine.id}-#{indicator.id}", "Salvo")
          ]
        end
        format.html { redirect_to routine, notice: "Etiquetas do indicador atualizadas.", status: :see_other }
      end
    else
      render_error(routine, indicator.id, indicator.errors.full_messages.to_sentence)
    end
  rescue ActiveRecord::RecordInvalid => error
    render_error(routine, indicator.id, error.record.errors.full_messages.to_sentence)
  end

  private

  def render_error(routine, indicator_id, message, status: :unprocessable_entity)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update("routine-indicator-labels-status-#{routine.id}-#{indicator_id}",
          helpers.tag.span(message, class: "text-danger")), status: status
      end
      format.html do
        if status == :forbidden
          head :forbidden
        else
          redirect_to routine, alert: message, status: :see_other
        end
      end
    end
  end
end
