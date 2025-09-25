class InvoiceNumber < ApplicationRecord
  belongs_to :invoice
  validates :number, presence: true
end
