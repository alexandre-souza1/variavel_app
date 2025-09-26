class CostCenter < ApplicationRecord
  has_many :invoices

  validates :name, presence: true, uniqueness: true
  validates :sector, presence: true

  enum sector: {
    rota: 'ROTA',
    rh: 'RH',
    seguranca: 'SEGURANÇA',
    gestao: 'GESTÃO',
    financeiro: 'FINANCEIRO',
    armazem: 'ARMAZEM'
  }
end
