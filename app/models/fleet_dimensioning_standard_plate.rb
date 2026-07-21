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
            }
  validates :plate_id,
            uniqueness: {
              scope: :fleet_dimensioning_id
            }
end
