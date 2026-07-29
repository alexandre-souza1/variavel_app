module Routines
  class CalculationService
    def self.call(...)
      new(...).call
    end

    def initialize(routine:, indicator:)
      @routine = routine
      @indicator = indicator
    end

    def call
      {
        value: calculated_value,
        goal: goal,
        achieved: achieved?,
        status: status,
        filled_days: filled_days,
        total_days: total_days,
        completion: completion,
        complete: complete?
      }
    end

    private

    attr_reader :routine, :indicator

    def values
      @values ||= routine
        .routine_values
        .where(routine_indicator: indicator)
        .where.not(value: nil)
    end

    def calculated_value
      return @calculated_value if defined?(@calculated_value)

      @calculated_value =
        case indicator.calculation_type
        when "manual_calculation"
          nil

        when "plus"
          values.sum(:value)

        when "ranged"
          values.average(:value)

        when "minimal"
          values.minimum(:value)

        when "maximal"
          values.maximum(:value)

        when "last_value"
          values.order(:reference_date).last&.value
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
      @total_days ||= (
        routine.period_start..routine.period_end
      ).count
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
