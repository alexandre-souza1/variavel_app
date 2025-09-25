json.extract! invoice, :id, :supplier_id, :budget_category_id, :number, :date, :total, :notes, :created_at, :updated_at
json.url invoice_url(invoice, format: :json)
