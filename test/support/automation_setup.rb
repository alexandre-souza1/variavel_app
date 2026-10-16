module AutomationSetup
  def setup_automation_data
    travel_to Time.zone.local(2026, 10, 16, 10)
    @owner = users(:one)
    @owner.update!(role: :user, sector: :fleet)
    @template = RoutineTemplate.create!(name: "Automação teste", sector: :fleet)
    category = @template.routine_categories.create!(name: "Despesas", position: 0)
    @indicator = category.routine_indicators.create!(name: "Despesa mensal", value_type: :currency,
      response_frequency: :monthly, calculation_type: :plus, position: 0)
    @routine = @template.routines.create!(created_by: @owner, title: "GEROT outubro",
      period_start: Date.current.beginning_of_month, period_end: Date.current.end_of_month)
    @category = BudgetCategory.create!(name: "Abastecimento", sector: :frota)
    @center = CostCenter.create!(name: "Operação teste", sector: :frota)
    @supplier = Supplier.create!(name: "Posto teste", cnpj: "12345678000199")
    @plan = @owner.action_plans.create!(name: "Plano teste de automações", public: false)
  end

  def finance_rule(**attributes)
    AutomationRule.new({ user: @owner, name: "Despesas no GEROT", source_key: "invoices", operation: "sum",
      period: "month", filters: { budget_category_id: @category.id.to_s }, action_key: "update_indicator",
      action_config: { routine_template_id: @template.id.to_s, routine_indicator_id: @indicator.id.to_s },
      schedule: "daily" }.merge(attributes))
  end

  def task_rule(**attributes)
    AutomationRule.new({ user: @owner, name: "Pendências", source_key: "tasks", operation: "count", period: "today",
      filters: { status: "pending", action_plan_id: @plan.id.to_s }, action_key: "notify",
      action_config: { title: "Revisar {{valor}} pendências", body: "Período {{periodo}}" }, schedule: "hourly" }.merge(attributes))
  end

  def create_automation_expense(amount, date: Date.current, purchaser: @owner, category: @category)
    Invoice.create!(code: "AUTO-#{SecureRandom.hex(4)}", supplier: @supplier, purchaser: purchaser,
      budget_category: category, date_issued: date, due_date: date,
      invoice_numbers_attributes: [{ number: SecureRandom.hex(3), amount: amount, cost_center: @center }])
  end

  def run_automation(rule, **options)
    rule.save! unless rule.persisted?
    Automations::Runner.call(rule, actor: @owner, **options)
  end
end
