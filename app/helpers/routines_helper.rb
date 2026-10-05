module RoutinesHelper
  def routine_status_label(routine)
    {
      "open" => "Aberta",
      "closed" => "Encerrada",
      "archived" => "Arquivada"
    }.fetch(routine.status, routine.status.humanize)
  end

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
      format_brl_currency(value)

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
    Routines::GoalEvaluation.call(indicator: indicator, value: value, goal: goal)
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

  def format_brl_currency(value)
    number_to_currency(
      value.to_d,
      unit: "R$ ",
      delimiter: ".",
      separator: ",",
      precision: 2
    )
  end

end
