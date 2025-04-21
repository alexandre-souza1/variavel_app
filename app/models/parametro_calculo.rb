class ParametroCalculo < ApplicationRecord
  validates :categoria, presence: true

  def self.valor_para(categoria:, nome:)
    find_by(categoria: categoria, nome: nome)&.valor
  end
end
