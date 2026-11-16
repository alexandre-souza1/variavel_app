class AddCreatedByToInvoices < ActiveRecord::Migration[7.1]
  def change
    add_reference :invoices, :created_by, foreign_key: { to_table: :users }, index: true
  end
end
