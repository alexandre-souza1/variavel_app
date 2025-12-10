class AddCostCenterToInvoiceNumbers < ActiveRecord::Migration[7.1]
  def change
    add_reference :invoice_numbers, :cost_center, foreign_key: true
  end
end
