class CreateInvoiceEmailImports < ActiveRecord::Migration[7.1]
  def change
    create_table :invoice_email_imports do |t|
      t.string :message_id, null: false
      t.string :sender, null: false
      t.string :subject
      t.datetime :received_at
      t.string :status, null: false, default: "processed"
      t.text :error_message
      t.bigint :invoice_id
      t.datetime :processed_at

      t.timestamps
    end

    add_index :invoice_email_imports, :message_id, unique: true
    add_index :invoice_email_imports, :status
    add_foreign_key :invoice_email_imports, :invoices
  end
end
