class GasolaSupply < ApplicationRecord
  FUELS = %w[dieselS10 dieselS10Aditivado dieselS500 gasolina gasolinaAditivada etanol etanolAditivado gas].freeze

  scope :consumption, -> { where(status: 'CONCLUDED', category: 'veículo', fuel: FUELS) }

  def valid_consumption?
    liters&.positive? && distance&.positive?
  end
end
