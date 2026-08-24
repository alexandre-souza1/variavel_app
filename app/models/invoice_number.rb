class InvoiceNumber < ApplicationRecord
  belongs_to :invoice
  belongs_to :cost_center  # novo
  validates :number, presence: true
  validates :amount, numericality: { greater_than_or_equal_to: 0 }

  def amount=(value)
    super(normalize_amount_value(value))
  end

  private

  def normalize_amount_value(value)
    return value unless value.is_a?(String)
    return value.gsub('.', '').tr(',', '.') if value.include?(',')

    value
  end
end
