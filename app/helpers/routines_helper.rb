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
        value,
        precision: 2,
        delimiter: ".",
        separator: ","
      )

    when "percentage"
      "#{number_with_precision(
        value,
        precision: 1,
        separator: ","
      )}%"

    when "currency"
      number_to_currency(value)

    else
      value

    end

  end

  def routine_cell_status(indicator, value, goal)
    return nil if value.blank?
    return nil if goal.blank?
    return nil if indicator.manual_calculation?

    case indicator.goal_direction

    when "greater_or_equal"
      value >= goal ? :success : :danger

    when "less_or_equal"
      value <= goal ? :success : :danger

    end
  end

end
