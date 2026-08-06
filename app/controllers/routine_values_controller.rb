class RoutineValuesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_routine_value

  def update
    ActiveRecord::Base.transaction do
      @routine_value.assign_attributes(
        normalized_routine_value_params.merge(
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

      progress_label:
        calculation[:progress_label],

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

  def normalized_routine_value_params
    permitted_params = routine_value_params
    value = permitted_params[:value]&.strip

    permitted_params[:value] =
      if value.blank?
        nil
      elsif numeric_indicator?
        normalize_numeric_value(value)
      elsif duration_indicator?
        normalize_duration_value(value)
      else
        value
      end

    permitted_params
  end

  def numeric_indicator?
    @routine_value.routine_indicator.value_type.in?(
      %w[integer decimal percentage currency]
    )
  end

  def duration_indicator?
    @routine_value.routine_indicator.duration?
  end

  def normalize_numeric_value(value)
    value.tr(",", ".")
  end

  def normalize_duration_value(value)
    value.tr(".", ":")
  end
end
