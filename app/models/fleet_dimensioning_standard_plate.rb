class FleetDimensioningStandardPlate < ApplicationRecord
  belongs_to :fleet_dimensioning
  belongs_to :plate

  validates :position,
            presence: true,
            numericality: {
              only_integer: true,
              greater_than_or_equal_to: 0
            },
            uniqueness: {
              scope: :fleet_dimensioning_id
            },
            unless: :special_route?
  validates :special_route,
            inclusion: { in: FleetAvailability::SPECIAL_ROUTES.keys },
            uniqueness: { scope: :fleet_dimensioning_id },
            allow_blank: true
  validates :plate_id,
            uniqueness: {
              scope: :fleet_dimensioning_id
            }

  validate :position_or_special_route

  def special_route?
    special_route.present?
  end

  private

  def position_or_special_route
    return if (position.present? && special_route.blank?) || (position.blank? && special_route.present?)

    errors.add(:base, "informe uma posição ou uma rota especial")
  end
end
