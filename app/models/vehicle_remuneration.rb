class VehicleRemuneration < ApplicationRecord
  belongs_to :remuneration_period
  has_many :remuneration_category_values, dependent: :destroy
  accepts_nested_attributes_for :remuneration_category_values, allow_destroy: true

  VEHICLE_TYPES = %w[ROTA VAN VESP AS].freeze

  validates :vehicle_type, presence: true, inclusion: { in: VEHICLE_TYPES }
  validates :vehicle_type, uniqueness: { scope: :remuneration_period_id }
  validates :fleet_quantity, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :km_remunerated, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  before_save :divide_km_remunerated

    private

  def divide_km_remunerated
    # Divide o km_remunerated por 2 se estiver presente e se foi alterado
    if km_remunerated.present? && km_remunerated_changed?
      self.km_remunerated = km_remunerated / 2.0
    end
  end
end
