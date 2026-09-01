class RoutinesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_routine, only: %i[
    show
    destroy
  ]

  def index
    @routines = Routine.visible_to(current_user)
      .includes(:routine_template, :created_by)
      .order(period_start: :desc)
  end

  def show
    @days = (@routine.period_start..@routine.period_end).to_a

    selected_indicator_ids = @routine.selected_indicator_ids

    @categories = @routine
                    .routine_template
                    .routine_categories
                    .includes(routine_indicators: :routine_indicator_targets)
                    .order(:position)
                    .select do |category|
                      category.routine_indicators.any? do |indicator|
                        selected_indicator_ids.include?(indicator.id)
                      end
                    end

    @indicators = @categories.flat_map do |category|
      category.routine_indicators.select do |indicator|
        selected_indicator_ids.include?(indicator.id)
      end
    end

    @expected_dates_by_indicator =
      @indicators.index_with do |indicator|
        indicator.reference_dates_between(
          @routine.period_start,
          @routine.period_end
        )
      end

    @expected_dates_index =
      @expected_dates_by_indicator.transform_values do |dates|
        dates.index_with(true)
      end

    @routine.ensure_expected_values!(indicators: @indicators)

    routine_values = @routine
                      .routine_values
                      .includes(routine_comments: :user)
                      .where(routine_indicator_id: @indicators.map(&:id))
                      .to_a

    @values_index = routine_values
                      .index_by do |value|
                        [value.routine_indicator_id, value.reference_date]
                      end

    @values_by_indicator_id =
      routine_values.group_by(&:routine_indicator_id)

    @frequency_sections = {
      "daily" => "Metas diárias",
      "weekly" => "Metas semanais",
      "monthly" => "Metas mensais"
    }

    @indicators_by_frequency_and_category = {}

    @frequency_sections.each_key do |frequency|
      @categories.each do |category|
        selected_indicators_for_category = category.routine_indicators.select do |indicator|
          selected_indicator_ids.include?(indicator.id) &&
            indicator.response_frequency == frequency
        end

        @indicators_by_frequency_and_category[
          [frequency, category.id]
        ] = selected_indicators_for_category
      end
    end

    @row_index = {}

    index = 0

    @frequency_sections.each_key do |frequency|
      @categories.each do |category|
        @indicators_by_frequency_and_category[[frequency, category.id]].to_a.each do |indicator|
          @row_index[indicator.id] = index
          index += 1
        end
      end
    end

    @calculation_results = {}

    @indicators.each do |indicator|
      @calculation_results[indicator.id] =
        Routines::CalculationService.call(
          routine: @routine,
          indicator: indicator,
          values: @values_by_indicator_id[indicator.id] || [],
          expected_reference_dates:
            @expected_dates_by_indicator[indicator]
        )
    end
  end

  def destroy
    @routine.destroy!

    redirect_to routines_path,
                notice: "Rotina removida com sucesso."
  end

  private

  def set_routine
    @routine = Routine.visible_to(current_user).includes(:routine_template).find(params[:id])
  end
end
