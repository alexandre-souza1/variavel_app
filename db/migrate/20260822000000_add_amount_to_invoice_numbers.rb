class AddAmountToInvoiceNumbers < ActiveRecord::Migration[7.1]
  def change
    add_column :invoice_numbers, :amount, :decimal, precision: 15, scale: 2, default: 0, null: false
  end
end
