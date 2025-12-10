class InvoiceNumber < ApplicationRecord
  belongs_to :invoice
  belongs_to :cost_center  # novo
  validates :number, presence: true
end
