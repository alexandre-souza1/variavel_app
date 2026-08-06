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
    @days = (@routine.period_start..@routine.period_end).to_a

    @categories = @routine
                    .routine_template
                    .routine_categories
                    .includes(routine_indicators: :routine_indicator_targets)
                    .order(:position)

    @indicators = @categories.flat_map(&:routine_indicators)

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
        @indicators_by_frequency_and_category[
          [frequency, category.id]
        ] = category.routine_indicators.select do |indicator|
          indicator.response_frequency == frequency
        end
      end
    end

    @row_index = {}

    index = 0

    @frequency_sections.each_key do |frequency|
      @categories.each do |category|
        @indicators_by_frequency_and_category[
          [frequency, category.id]
        ].each do |indicator|
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
    @routine = Routine.find(params[:id])
  end
end
