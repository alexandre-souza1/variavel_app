class CreateInvoices < ActiveRecord::Migration[7.1]
  def change
    create_table :invoices do |t|
      t.references :supplier, null: false, foreign_key: true
      t.references :budget_category, null: false, foreign_key: true
      t.string :number
      t.date :date
      t.decimal :total
      t.text :notes

      t.timestamps
    end
  end
end
