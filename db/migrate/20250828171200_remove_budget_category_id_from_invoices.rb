class RemoveBudgetCategoryIdFromInvoices < ActiveRecord::Migration[7.1]
  def change
    remove_column :invoices, :budget_category_id, :bigint
  end
end
