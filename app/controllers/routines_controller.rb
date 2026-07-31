class RoutinesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_routine, only: %i[
    show
    destroy
  ]

  def index
    @routines = Routine
      .includes(:routine_template, :created_by)
      .order(period_start: :desc)
  end

  def show
    @routine.ensure_expected_values!

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

    @row_index = {}

    index = 0

    @categories.each do |category|
      category.routine_indicators.each do |indicator|
        @row_index[indicator.id] = index
        index += 1
      end
    end

    @calculation_results = {}

    @categories.each do |category|
      category.routine_indicators.each do |indicator|
        @calculation_results[indicator.id] =
          Routines::CalculationService.call(
            routine: @routine,
            indicator: indicator
          )
      end
    end
  end

  def destroy
    @routine.destroy!

    redirect_to routines_path,
                notice: "Rotina removida com sucesso."
  end

  private

  def set_routine
    @routine = Routine.find(params[:id])
  end
end
