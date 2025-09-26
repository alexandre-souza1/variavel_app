class RemoveBudgetCategoryFromInvoices < ActiveRecord::Migration[7.1]
  def change
    remove_column :invoices, :budget_category, :string
  end
end
