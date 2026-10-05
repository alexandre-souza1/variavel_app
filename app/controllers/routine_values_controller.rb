class RoutineValuesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_routine_value

  def update
    if @routine_value.routine.closed? || @routine_value.routine.archived?
      render json: { error: "Esta rotina não aceita mais preenchimentos." },
             status: :unprocessable_entity
      return
    end

    @routine_value.with_lock do
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
        @generated_task = Routines::DeviationTaskGenerator.call(
          routine_value: @routine_value, actor: current_user, previous_value: previous_value
        )
      end
    end

    calculation =
      Routines::CalculationService.call(
        routine: @routine_value.routine,
        indicator: @routine_value.routine_indicator
      )

    target =
      @routine_value
        .routine_indicator
        .target_for(@routine_value.reference_date)
        &.goal

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

      cell_status:
        helpers.routine_cell_status(
          @routine_value.routine_indicator,
          @routine_value.value,
          target
        ),

      generated_task_id: @generated_task&.id,
      generated_task_created: @generated_task&.previously_new_record? || false,
      generated_task_url: (@generated_task && action_plan_path(@routine_value.routine.action_plan, task_id: @generated_task.id)),

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
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  private

  def set_routine_value
    @routine_value = RoutineValue.where(routine_id: Routine.visible_to(current_user).select(:id)).find(params[:id])
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
