class AddDocumentUrlsToInvoices < ActiveRecord::Migration[7.1]
  def change
    add_column :invoices, :document_urls, :text, array: true, default: []
  end
end
