class RoutineGeneratorsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_template, only: %i[new create]
  before_action :set_routine, only: %i[edit update]

  def new
  end

  def create
    routine = Routines::Generator.call(
      template: @template,
      period_start: Date.parse(params[:period_start]),
      period_end: Date.parse(params[:period_end]),
      created_by: current_user,
      indicator_ids: params[:indicator_ids]&.reject(&:blank?)
    )

    redirect_to routine,
                notice: "Rotina criada com sucesso."
  end

  def edit
    return unless ensure_editable_routine
  end

  def update
    return unless ensure_editable_routine

    selected_indicator_ids = params[:indicator_ids]&.reject(&:blank?)
    
    Routines::IndicatorUpdater.call(
      routine: @routine,
      indicator_ids: selected_indicator_ids
    )

    redirect_to @routine,
                notice: "Indicadores atualizados com sucesso."
  end

  private

  def set_template
    @template = RoutineTemplate.visible_to(current_user).find(params[:routine_template_id])
  end

  def set_routine
    @routine = Routine.visible_to(current_user).includes(:routine_template).find(params[:routine_id])
  end

  def ensure_editable_routine
    return true unless @routine.closed? || @routine.archived?

    redirect_to @routine, alert: "Esta rotina não permite mais editar os indicadores."
    false
  end
end
