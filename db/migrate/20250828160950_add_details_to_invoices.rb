class AddDetailsToInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :invoices, :code, :string
    add_index :invoices, :code, unique: true

    add_column :invoices, :date_issued, :date
    add_column :invoices, :due_date, :date

    add_column :invoices, :purchaser, :string
    add_column :invoices, :budget_category, :integer
    add_column :invoices, :cost_center, :integer
  end
end
