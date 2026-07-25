class RoutineGeneratorsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_template

  def new
  end

  def create
    routine = Routines::Generator.call(
      template: @template,
      period_start: Date.parse(params[:period_start]),
      period_end: Date.parse(params[:period_end]),
      created_by: current_user
    )

    redirect_to routine,
                notice: "Rotina criada com sucesso."
  end

  private

  def set_template
    @template = RoutineTemplate.find(params[:routine_template_id])
  end
end
