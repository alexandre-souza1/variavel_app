module Routines
  class CalculationService
    NUMERIC_VALUE_TYPES = %w[
      integer
      decimal
      percentage
      currency
    ].freeze

    DURATION_VALUE_TYPE = "duration".freeze

    def self.call(...)
      new(...).call
    end

    def initialize(
      routine:,
      indicator:,
      values: nil,
      expected_reference_dates: nil
    )
      @routine = routine
      @indicator = indicator
      @preloaded_values = values
      @expected_reference_dates = expected_reference_dates
    end

    def call
      result = calculated_value
      target = goal

      {
        value: result,
        goal: target,
        achieved: achieved?(result, target),
        status: status(result, target),
        filled_days: filled_days,
        total_days: total_days,
        progress_label: progress_label,
        completion: completion,
        complete: complete?
      }
    end

    private

    attr_reader :routine, :indicator

    # Retorna sempre um Array<RoutineValue>.
    #
    # Isso evita diferenças entre:
    # - valores pré-carregados;
    # - ActiveRecord::Relation vindo do banco.
    def values
      @values ||= begin
        records =
          if @preloaded_values
            @preloaded_values
          else
            routine
              .routine_values
              .where(routine_indicator: indicator)
              .where(reference_date: expected_reference_dates)
              .to_a
          end

        records.select do |routine_value|
          routine_value.value.present? &&
            expected_reference_dates.include?(
              routine_value.reference_date
            )
        end
      end
    end

    def calculated_value
      return manual_value if indicator.manual_calculation?

      case indicator.calculation_type
      when "ranged"
        average_value

      when "plus"
        sum_value

      when "last_value"
        last_value

      when "minimal"
        minimum_value

      when "maximal"
        maximum_value
      end
    end

    # Para indicadores manuais, estou usando o último preenchimento.
    #
    # Caso "manual" no seu Gerot deva mostrar sempre vazio no resultado,
    # troque o conteúdo deste método por:
    #
    # nil
    def manual_value
      last_value
    end

    def average_value
      return average_duration if duration_indicator?
      return unless numeric_indicator?

      numbers = numeric_values
      return if numbers.empty?

      numbers.sum / numbers.length
    end

    def sum_value
      return sum_duration if duration_indicator?
      return unless numeric_indicator?

      numbers = numeric_values
      return if numbers.empty?

      numbers.sum
    end

    def minimum_value
      pair = comparable_value_pairs.min_by do |_, comparable|
        comparable
      end

      pair&.first
    end

    def maximum_value
      pair = comparable_value_pairs.max_by do |_, comparable|
        comparable
      end

      pair&.first
    end

    def last_value
      values
        .max_by(&:reference_date)
        &.value
    end

    def numeric_values
      values.filter_map do |routine_value|
        decimal_value(routine_value.value)
      end
    end

    # Mantemos o valor original junto com sua versão comparável.
    #
    # Exemplo de hora:
    # ["05:13", 313]
    #
    # Assim conseguimos comparar usando minutos, mas retornamos "05:13"
    # para o helper e para o frontend.
    def comparable_value_pairs
      values.filter_map do |routine_value|
        original_value = routine_value.value
        comparable = comparable_value(original_value)

        next if comparable.nil?

        [original_value, comparable]
      end
    end

    def numeric_indicator?
      indicator.value_type.in?(NUMERIC_VALUE_TYPES)
    end

    def duration_indicator?
      indicator.value_type == DURATION_VALUE_TYPE
    end

    def goal
      return @goal if defined?(@goal)

      @goal = indicator
        .target_for(routine.period_start)
        &.goal
    end

    def filled_days
      @filled_days ||= values.length
    end

    def total_days
      @total_days ||= expected_reference_dates.length
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

    def achieved?(result = calculated_value, target = goal)
      return nil if indicator.manual_calculation?
      return nil if target.blank?
      return nil if result.blank?

      comparable_result = comparable_value(result)
      comparable_target = comparable_value(target)

      return nil if comparable_result.nil?
      return nil if comparable_target.nil?

      case indicator.goal_direction
      when "greater_or_equal"
        comparable_result >= comparable_target

      when "less_or_equal"
        comparable_result <= comparable_target
      end
    end

    def status(result = calculated_value, target = goal)
      return :manual if indicator.manual_calculation?
      return :no_data if filled_days.zero?
      return :no_goal if target.blank?
      return :partial unless complete?

      achieved?(result, target) ? :success : :danger
    end

    def comparable_value(value)
      return if value.blank?

      case indicator.value_type
      when "integer", "decimal", "percentage", "currency"
        decimal_value(value)

      when "date"
        Date.iso8601(value.to_s)

      when "time"
        time_in_minutes(value)

      when "duration"
        duration_in_seconds(value)

      when "boolean"
        boolean_as_number(value)

      when "text"
        value.to_s

      else
        value.to_s
      end
    rescue Date::Error, ArgumentError
      nil
    end

    def decimal_value(value)
      normalized = value.to_s.strip.tr(",", ".")

      BigDecimal(normalized)
    rescue ArgumentError
      nil
    end

    def time_in_minutes(value)
      match = value.to_s.match(
        /\A(?<hour>[01]\d|2[0-3]):(?<minute>[0-5]\d)\z/
      )

      return unless match

      hour = match[:hour].to_i
      minute = match[:minute].to_i

      (hour * 60) + minute
    end

    def average_duration
      seconds = duration_values
      return if seconds.empty?

      average_seconds = (seconds.sum.to_f / seconds.length).round

      format_duration_seconds(average_seconds)
    end

    def sum_duration
      seconds = duration_values
      return if seconds.empty?

      format_duration_seconds(seconds.sum)
    end

    def duration_values
      values.filter_map do |routine_value|
        duration_in_seconds(routine_value.value)
      end
    end

    def duration_in_seconds(value)
      match = value.to_s.tr(".", ":").match(
        /\A(?<minute>\d+):(?<second>[0-5]\d)\z/
      )

      return unless match

      (match[:minute].to_i * 60) + match[:second].to_i
    end

    def format_duration_seconds(total_seconds)
      total_seconds = total_seconds.to_i
      minutes = total_seconds / 60
      seconds = total_seconds % 60

      format("%<minutes>d:%<seconds>02d", minutes: minutes, seconds: seconds)
    end

    def boolean_as_number(value)
      case value.to_s
      when "true", "1"
        1
      when "false", "0"
        0
      end
    end
  end
end
