class InvoiceNumber < ApplicationRecord
  belongs_to :invoice
  belongs_to :cost_center  # novo
  validates :number, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  before_validation :normalize_amount

  private

  def normalize_amount
    self.amount = amount.to_s.gsub('.', '').tr(',', '.') if amount.is_a?(String) && amount.include?(',')
  end
end
