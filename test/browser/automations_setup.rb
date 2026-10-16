# RAILS_ENV=test bin/rails runner test/browser/automations_setup.rb
abort "Use somente o banco de testes" unless Rails.env.test?
email = "browser-automations@example.test"
abort "Dados do navegador já existem; remova-os antes de preparar novamente." if User.exists?(email: email)
user = User.create!(email: email, name: "Automações navegador", password: "password123", role: :user, sector: :fleet)
template = RoutineTemplate.create!(name: "GEROT navegador automações", sector: :fleet)
category = template.routine_categories.create!(name: "Controle", position: 0)
indicator = category.routine_indicators.create!(name: "Despesas mensais", position: 0, response_frequency: :monthly, value_type: :currency, calculation_type: :plus)
routine = template.routines.create!(created_by: user, title: "GEROT navegador", period_start: Date.current.beginning_of_month, period_end: Date.current.end_of_month)
budget = BudgetCategory.create!(name: "Despesas navegador automações", sector: :frota)
second_budget = BudgetCategory.create!(name: "Manutenção empilhadeiras navegador automações", sector: :frota)
center = CostCenter.create!(name: "Centro navegador automações", sector: :frota)
supplier = Supplier.create!(name: "Fornecedor navegador automações", cnpj: "98765432000198")
Invoice.create!(code: "BROWSER-AUTOMATIONS", supplier: supplier, purchaser: user, budget_category: budget,
  date_issued: Date.current, due_date: Date.current, invoice_numbers_attributes: [{ number: "AUTO-01", amount: "123.45", cost_center: center }])
Invoice.create!(code: "BROWSER-AUTOMATIONS-02", supplier: supplier, purchaser: user, budget_category: second_budget,
  date_issued: Date.current, due_date: Date.current, invoice_numbers_attributes: [{ number: "AUTO-02", amount: "76.55", cost_center: center }])
plan = user.action_plans.create!(name: "Plano navegador automações", public: false)
plan.buckets.first.tasks.create!(title: "Revisar despesa", creator: user, due_at: 1.hour.ago)
FileUtils.mkdir_p(Rails.root.join("tmp/automations"))
File.write(Rails.root.join("tmp/automations/browser.json"), { template_id: template.id, indicator_id: indicator.id,
  budget_category_id: budget.id, second_budget_category_id: second_budget.id, action_plan_id: plan.id, user_id: user.id, routine_id: routine.id }.to_json)
puts "Dados de navegação preparados no banco de testes."
