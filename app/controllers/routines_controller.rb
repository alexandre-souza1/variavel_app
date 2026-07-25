class RoutinesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_routine, only: :show

  def index
    @routines = Routine
      .includes(:routine_template, :created_by)
      .order(period_start: :desc)
  end

  def show
    @days = (@routine.period_start..@routine.period_end).to_a

    @categories = @routine
                    .routine_template
                    .routine_categories
                    .includes(routine_indicators: :routine_values)
                    .order(:position)

    @values_index = @routine
                      .routine_values
                      .index_by do |value|
                        [value.routine_indicator_id, value.reference_date]
                      end
  end

  private

  def set_routine
    @routine = Routine.find(params[:id])
  end
end
