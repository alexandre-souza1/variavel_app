module RoutinesHelper
  def routine_weekday_abbr(date)
    %w[Dom Seg Ter Qua Qui Sex Sab][date.wday]
  end

  def routine_value_display(indicator, value)
    return "-" if value.blank?

    case indicator.value_type
    when "integer"
      value.to_i

    when "decimal"
      number_with_precision(
        value.to_d,
        precision: 2,
        delimiter: ".",
        separator: ","
      )

    when "percentage"
      "#{number_with_precision(
        value.to_d,
        precision: 1,
        separator: ","
      )}%"

    when "currency"
      number_to_currency(value.to_d)

    when "boolean"
      value.to_s.in?(%w[true 1]) ? "Sim" : "Não"

    when "date"
      format_routine_date(value)

    when "time"
      value.to_s[0, 5]

    when "duration"
      value.to_s.tr(".", ":")

    else
      value.to_s
    end
  end

  def routine_cell_status(indicator, value, goal)
    return nil if value.blank?
    return nil if goal.blank?
    return nil if indicator.manual_calculation?

    comparable_value = routine_comparable_value(indicator, value)
    comparable_goal = routine_comparable_value(indicator, goal)

    return nil if comparable_value.nil? || comparable_goal.nil?

    case indicator.goal_direction
    when "greater_or_equal"
      comparable_value >= comparable_goal ? :success : :danger

    when "less_or_equal"
      comparable_value <= comparable_goal ? :success : :danger
    end
  end

  private

  def format_routine_date(value)
    date =
      case value
      when Date
        value
      else
        Date.iso8601(value.to_s)
      end

    l(date)
  rescue Date::Error, ArgumentError
    value.to_s
  end

  def routine_comparable_value(indicator, value)
    case indicator.value_type
    when "integer", "decimal", "percentage", "currency"
      BigDecimal(value.to_s.tr(",", "."))

    when "date"
      Date.iso8601(value.to_s)

    when "time"
      hour, minute = value.to_s.split(":").map(&:to_i)
      (hour * 60) + minute

    when "duration"
      match = value.to_s.tr(".", ":").match(
        /\A(?<minutes>\d+):(?<seconds>[0-5]\d)\z/
      )

      return unless match

      minutes = match[:minutes].to_i
      seconds = match[:seconds].to_i

      (minutes * 60) + seconds

    when "boolean"
      value.to_s.in?(%w[true 1]) ? 1 : 0

    else
      value.to_s
    end
  rescue ArgumentError
    nil
  end
end
