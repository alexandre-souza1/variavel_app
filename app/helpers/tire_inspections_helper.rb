module TireInspectionsHelper
  def tire_panel_path(options = {})
    options = options.except("view", :view, "load", :load)
    return tire_schedule_path(options) if @schedule_view
    return tire_pressure_path(options) if @pressure_view

    tire_inspections_path(options)
  end

  def tire_page_details
    if @schedule_view
      ["Aferições de pneus", "Organize os vencimentos e mantenha as aferições de sulco dentro de 30 dias."]
    elsif @pressure_view
      ["Calibragem de pneus", "Acompanhe as pressões baixas e o resultado das próximas leituras."]
    else
      ["Divergências de sulco", "Confira os aumentos de medida entre aferições do mesmo pneu."]
    end
  end

  def inspection_schedule_label(row)
    case row[:status]
    when "overdue" then "Vencida há #{pluralize(-row[:days_left], 'dia', 'dias')}"
    when "today" then "Vence hoje"
    when "soon", "ok" then "Vence em #{pluralize(row[:days_left], 'dia', 'dias')}"
    else "Sem histórico"
    end
  end

  def pressure_status_label(status)
    { "persisted" => "Permaneceu baixa", "normalized" => "Normalizou", "pending" => "Última leitura baixa no período", "current_low" => "Incorreto · pressão baixa no mês atual", "awaiting_month" => "Pressão baixa · sem aferição no mês atual", "unknown" => "Sem comparação válida" }.fetch(status)
  end
end
