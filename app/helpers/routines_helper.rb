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

end
