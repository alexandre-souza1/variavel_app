module AutomationRulesHelper
  def automation_source_label(rule)
    Automations::Catalog::SOURCES.dig(rule.source_key, :label) || rule.source_key
  end

  def automation_action_label(rule)
    Automations::Catalog::ACTIONS.dig(rule.action_key, :label) || rule.action_key
  end

  def automation_value(value, operation)
    return "—" if value.nil?
    operation == "count" ? number_with_delimiter(value.to_d.to_i, delimiter: ".") : number_to_currency(value, unit: "R$ ", separator: ",", delimiter: ".")
  end

  def automation_indicator_options
    @indicators.map do |indicator|
      frequency = { "daily" => "diário", "weekly" => "semanal", "monthly" => "mensal" }.fetch(indicator.response_frequency)
      ["#{indicator.name} · #{frequency} · #{indicator.value_type_label}", indicator.id,
        { "data-template-id" => indicator.routine_category.routine_template_id, "data-frequency" => indicator.response_frequency }]
    end
  end

  def automation_schedule_text(rule)
    return "Execução manual" if rule.schedule == "manual"
    return "A cada hora · Brasília" if rule.schedule == "hourly"
    suffix = case rule.schedule
    when "weekly" then " · #{Routine::WEEKDAY_LABELS[rule.weekday]}"
    when "monthly" then " · dia #{rule.month_day}"
    end
    "#{AutomationRule::SCHEDULES.key(rule.schedule)}#{suffix} às #{format('%02d', rule.execution_hour)}h · Brasília"
  end

  def automation_period_text(start_date, end_date)
    first = start_date.present? ? l(start_date.to_date) : "Início do histórico"
    "#{first} até #{l(end_date.to_date)}"
  end

  def automation_filter_summary(rule)
    case rule.source_key
    when "invoices"
      ids = Automations::Configuration.category_ids(rule.filters)
      categories = Automations::Configuration.categories_for(rule.user).where(id: ids).index_by { |category| category.id.to_s }
      names = ids.map { |id| categories[id]&.name || "Categoria indisponível" }.sort
      [rule.filters["sector"].present? ? BudgetCategory.sectors[rule.filters["sector"]] : "Todos os setores permitidos",
       names.presence&.join(", ") || "Todas as categorias"].join(" · ")
    when "tasks"
      plan = ActionPlan.visible_to(rule.user).find_by(id: rule.filters["action_plan_id"]) if rule.filters["action_plan_id"].present?
      [Automations::Sources::Tasks::STATUSES[rule.filters["status"]],
       rule.filters["action_plan_id"].present? ? (plan&.name || "Plano indisponível") : "Todos os planos permitidos e Entrada",
       ("Somente minhas tarefas" if rule.filters["only_mine"] == "1")].compact.join(" · ")
    when "fleet" then Automations::Sources::Fleet::STATUSES[rule.filters["status"]]
    end
  end
end
