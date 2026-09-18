class CreateInvoiceEmailImportSettings < ActiveRecord::Migration[7.1]
  def change
    create_table :invoice_email_import_settings do |t|
      t.string :sender_email, null: false, default: "postoparadao1@gmail.com"
      t.string :imap_folder, null: false, default: "INBOX"
      t.string :schedule_time, null: false, default: "07:00"
      t.references :purchaser, foreign_key: { to_table: :users }
      t.references :budget_category, foreign_key: true
      t.references :fallback_cost_center, foreign_key: { to_table: :cost_centers }
      t.timestamps
    end
  end
end
