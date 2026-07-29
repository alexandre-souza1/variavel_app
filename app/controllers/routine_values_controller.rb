class RoutineValuesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_routine_value

  def update
    @routine_value.update!(
      routine_value_params.merge(
        updated_by: current_user
      )
    )

    calculation =
      Routines::CalculationService.call(
        routine: @routine_value.routine,
        indicator: @routine_value.routine_indicator
      )

    render json: {
      value: @routine_value.value,

      formatted_value:
        helpers.routine_value_display(
          @routine_value.routine_indicator,
          @routine_value.value
        ),

      calculated_value:
        calculation[:value],

      formatted_calculated_value:
        helpers.routine_value_display(
          @routine_value.routine_indicator,
          calculation[:value]
        ),

      goal:
        calculation[:goal],

      achieved:
        calculation[:achieved],

      status:
        calculation[:status],

      filled_days:
        calculation[:filled_days],

      total_days:
        calculation[:total_days],

      completion:
        calculation[:completion],

      complete:
        calculation[:complete]
    }
  end

  private

  def set_routine_value
    @routine_value = RoutineValue.find(params[:id])
  end

  def routine_value_params
    params.require(:routine_value).permit(:value)
  end
end
