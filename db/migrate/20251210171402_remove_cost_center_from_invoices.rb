class RemoveCostCenterFromInvoices < ActiveRecord::Migration[7.1]
  def change
    remove_reference :invoices, :cost_center, foreign_key: true
  end
end
