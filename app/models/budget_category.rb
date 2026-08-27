class BudgetCategory < ApplicationRecord
  has_many :invoices

  USER_SECTOR_BY_CATEGORY_SECTOR = {
    'frota' => :fleet,
    'rota' => :du,
    'as' => :du,
    'rh' => :hr,
    'seguranca' => :safety,
    'gestao' => :planning,
    'financeiro' => :finance,
    'armazem' => :warehouse
  }.freeze

  validates :name, presence: true, uniqueness: true
  validates :sector, presence: true

  enum sector: {
    frota: 'FROTA',
    rota: 'ROTA',
    as: 'AS',
    rh: 'RH',
    seguranca: 'SEGURANÇA',
    gestao: 'GESTÃO',
    financeiro: 'FINANCEIRO',
    armazem: 'ARMAZEM'
  }

  def user_sector
    USER_SECTOR_BY_CATEGORY_SECTOR[sector.to_s]
  end
end
