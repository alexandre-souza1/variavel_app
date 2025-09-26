class CreateInvoiceNumbers < ActiveRecord::Migration[7.1]
  def change
    create_table :invoice_numbers do |t|
      t.string :number
      t.references :invoice, null: false, foreign_key: true

      t.timestamps
    end
  end
end
