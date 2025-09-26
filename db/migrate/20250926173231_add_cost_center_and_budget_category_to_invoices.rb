class AddCostCenterAndBudgetCategoryToInvoices < ActiveRecord::Migration[7.1]
  def change
    add_reference :invoices, :cost_center, foreign_key: true
    add_reference :invoices, :budget_category, foreign_key: true
  end
end
