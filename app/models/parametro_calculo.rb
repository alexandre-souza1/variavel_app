class ParametroCalculo < ApplicationRecord
  validates :categoria, :nome, presence: true
  validates :nome, uniqueness: { scope: :categoria }, on: :create
  validates :valor, numericality: { greater_than_or_equal_to: 0 }
  attr_accessor :effective_on
  validate :valid_version
  after_save :record_rate_version
  before_destroy :retain_rate_history

  def self.valor_para(categoria:, nome:, date: nil)
    if date
      value = CalculationRateVersion.value_on(categoria: categoria, nome: nome, date: date)
      return value if value
      return nil if CalculationRateVersion.exists?(categoria: categoria, nome: nome)
    end
    find_by(categoria: categoria, nome: nome)&.valor
  end

  private

  def valid_version
    if persisted? && (will_save_change_to_categoria? || will_save_change_to_nome?)
      errors.add(:base, 'Categoria e nome identificam o histórico e não podem ser alterados.')
    end
    Date.iso8601(effective_on.to_s) if effective_on.present?
  rescue Date::Error
    errors.add(:effective_on, 'deve ser uma data válida')
  end

  def record_rate_version
    return unless effective_on.present? || saved_change_to_valor? || saved_change_to_categoria? || saved_change_to_nome?
    date = effective_on.present? ? Date.iso8601(effective_on.to_s) : Date.current
    CalculationRateVersion.create!(categoria: categoria, nome: nome, valor: valor, effective_on: date)
  end

  def retain_rate_history
    errors.add(:base, 'Parâmetros com histórico devem ser alterados com uma nova vigência, não excluídos.')
    throw :abort
  end
end
