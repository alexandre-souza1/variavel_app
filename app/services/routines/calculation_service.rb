module Routines
  class CalculationService
    def self.call(...)
      new(...).call
    end

    def initialize(routine:, indicator:, values: nil, expected_reference_dates: nil)
      @routine = routine
      @indicator = indicator
      @preloaded_values = values
      @expected_reference_dates = expected_reference_dates
    end

    def call
      {
        value: calculated_value,
        goal: goal,
        achieved: achieved?,
        status: status,
        filled_days: filled_days,
        total_days: total_days,
        progress_label: progress_label,
        completion: completion,
        complete: complete?
      }
    end

    private

    attr_reader :routine, :indicator

    def values
      @values ||= begin
        if @preloaded_values
          @preloaded_values.select do |routine_value|
            routine_value.value.present? &&
              expected_reference_dates.include?(
                routine_value.reference_date
              )
          end
        else
          routine
            .routine_values
            .where(routine_indicator: indicator)
            .where(reference_date: expected_reference_dates)
            .where.not(value: nil)
        end
      end
    end

    def calculated_value
      return @calculated_value if defined?(@calculated_value)

      @calculated_value =
        case indicator.calculation_type
        when "manual_calculation"
          nil

        when "plus"
          if @preloaded_values
            values.sum(&:value)
          else
            values.sum(:value)
          end

        when "ranged"
          if @preloaded_values
            return nil if values.empty?

            values.sum(&:value) / values.count
          else
            values.average(:value)
          end

        when "minimal"
          if @preloaded_values
            values.map(&:value).min
          else
            values.minimum(:value)
          end

        when "maximal"
          if @preloaded_values
            values.map(&:value).max
          else
            values.maximum(:value)
          end

        when "last_value"
          if @preloaded_values
            values.max_by(&:reference_date)&.value
          else
            values.order(:reference_date).last&.value
          end
        end
    end

    def goal
      return @goal if defined?(@goal)

      @goal = indicator
        .target_for(routine.period_start)
        &.goal
    end

    def filled_days
      @filled_days ||= values.count
    end

    def total_days
      @total_days ||= expected_reference_dates.count
    end

    def expected_reference_dates
      @expected_reference_dates ||=
        indicator.reference_dates_between(
          routine.period_start,
          routine.period_end
        )
    end

    def progress_label
      case indicator.response_frequency
      when "daily"
        "dias"
      when "weekly"
        "semanas"
      when "monthly"
        "meses"
      else
        "preenchimentos"
      end
    end

    def completion
      return 0.0 if total_days.zero?

      ((filled_days.to_f / total_days) * 100).round(1)
    end

    def complete?
      filled_days >= total_days
    end

    def achieved?
      return nil if indicator.manual_calculation?
      return nil if goal.nil?
      return nil if calculated_value.nil?

      case indicator.goal_direction
      when "greater_or_equal"
        calculated_value >= goal

      when "less_or_equal"
        calculated_value <= goal
      end
    end

    def status
      return :manual if indicator.manual_calculation?
      return :no_data if filled_days.zero?
      return :no_goal if goal.nil?
      return :partial unless complete?

      achieved? ? :success : :danger
    end
  end
end
