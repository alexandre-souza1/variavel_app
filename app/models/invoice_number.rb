class InvoiceNumber < ApplicationRecord
  belongs_to :invoice
  belongs_to :cost_center  # novo
  validates :number, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
end
