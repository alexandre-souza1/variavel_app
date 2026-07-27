class RoutineValuesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_routine_value

  def update
    @routine_value.update!(routine_value_params)

    render json: {
      value: @routine_value.value,
      formatted_value: helpers.routine_value_display(
        @routine_value.routine_indicator,
        @routine_value.value
      )
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
