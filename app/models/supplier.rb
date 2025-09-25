class Supplier < ApplicationRecord
  has_many :invoices, dependent: :destroy
  validates :name, :cnpj, presence: true
  validates :cnpj, uniqueness: true
end
