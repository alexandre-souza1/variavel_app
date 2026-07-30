class RoutineValuesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_routine_value

  def update
    ActiveRecord::Base.transaction do
      @routine_value.assign_attributes(
        routine_value_params.merge(
          updated_by: current_user
        )
      )

      value_changed =
        @routine_value.will_save_change_to_value?

      @routine_value.save!

      if value_changed
        previous_value, new_value =
          @routine_value.saved_change_to_value

        @routine_value.routine.routine_activities.create!(
          user: current_user,
          routine_value: @routine_value,
          activity_type: :value_changed,
          previous_value: previous_value,
          new_value: new_value
        )
      end
    end

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
