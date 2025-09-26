class AddPurchaserIdToInvoices < ActiveRecord::Migration[7.1]
  def change
    add_reference :invoices, :purchaser, foreign_key: { to_table: :users }
    remove_column :invoices, :purchaser, :string
  end
end
