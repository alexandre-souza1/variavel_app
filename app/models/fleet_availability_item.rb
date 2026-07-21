class FleetAvailabilityItem < ApplicationRecord
  belongs_to :fleet_availability
  belongs_to :plate
  has_many :fleet_availability_changes,
         dependent: :destroy

  enum status: {
    available: 0,
    exchange: 1,
    unavailable: 2
  }

  enum :reason, {
    maintenance: "maintenance",
    breakdown: "breakdown",
    accident: "accident",
    document: "document",
    other: "other"
  }, prefix: true

   scope :ordered, -> { order(:position) }

  validates :plate_id,
            uniqueness: {
              scope: :fleet_availability_id
            }

  validates :position,
            numericality: {
              greater_than_or_equal_to: 0
            }

  def status_badge_class
    case status
    when "available"
      "bg-success"
    when "exchange"
      "bg-warning text-dark"
    when "unavailable"
      "bg-danger"
    end
  end

  def status_label
    case status
    when "available"
      "Disponível"
    when "exchange"
      "Apta para troca"
    when "unavailable"
      "Indisponível"
    end
  end
end
