class CalculationRateVersion < ApplicationRecord
  validates :categoria, :nome, :valor, presence: true
  def readonly? = persisted?

  def self.value_on(categoria:, nome:, date:)
    where(categoria: categoria, nome: nome)
      .where('effective_on IS NULL OR effective_on <= ?', date)
      .order(Arel.sql('effective_on DESC NULLS LAST, id DESC')).first&.valor
  end
end
