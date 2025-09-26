class Supplier < ApplicationRecord
  has_many :invoices, dependent: :destroy
  validates :name, :cnpj, presence: true
  validates :cnpj, uniqueness: true

  # Validação opcional para formatar o CNPJ
  before_save :format_cnpj

  private

  def format_cnpj
    # Remove caracteres não numéricos e formata
    self.cnpj = cnpj.gsub(/\D/, '') if cnpj.present?
  end
end
