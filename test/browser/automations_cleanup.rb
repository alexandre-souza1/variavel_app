# RAILS_ENV=test bin/rails runner test/browser/automations_cleanup.rb
abort "Use somente o banco de testes" unless Rails.env.test?
user = User.find_by(email: "browser-automations@example.test")
if user
  rules = user.automation_rules
  AutomationRun.where(automation_rule_id: rules.select(:id)).delete_all
  rules.destroy_all
  user.notifications.destroy_all
  Routine.where(created_by: user).destroy_all
  Invoice.where(purchaser: user).destroy_all
  user.destroy!
end
RoutineTemplate.find_by(name: "GEROT navegador automações")&.destroy!
BudgetCategory.find_by(name: "Despesas navegador automações")&.destroy!
BudgetCategory.find_by(name: "Manutenção empilhadeiras navegador automações")&.destroy!
CostCenter.find_by(name: "Centro navegador automações")&.destroy!
Supplier.find_by(name: "Fornecedor navegador automações")&.destroy!
puts "Dados temporários das automações removidos do banco de testes."
