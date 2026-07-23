class FleetAvailabilityItem < ApplicationRecord
  belongs_to :fleet_availability
  belongs_to :plate
  has_many :fleet_availability_changes,
         dependent: :destroy

  enum status: {
    available: 0,
    exchange: 1,
    unavailable: 2,
    special_route: 3
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
  validates :position,
            uniqueness: {
              scope: :fleet_availability_id,
              conditions: -> { where(status: FleetAvailabilityItem.statuses[:available]) },
              message: "já está ocupada por outra placa disponível"
            },
            if: :available?
  validate :special_route_is_valid
  validate :special_route_is_active
  validate :special_route_status_has_route
  validate :special_route_quantity_is_available
  validate :van_route_requires_van_plate
  validate :available_position_is_dimensioned

  def status_badge_class
    case status
    when "available"
      "bg-success"
    when "exchange"
      "bg-secondary"
    when "unavailable"
      "bg-danger"
    when "special_route"
      "bg-info"
    end
  end

  def status_label
    case status
    when "available"
      "Na disponibilidade"
    when "exchange"
      "No depósito"
    when "unavailable"
      "Indisponível"
    when "special_route"
      special_route_label
    end
  end

  def special_route_label
    FleetAvailability::SPECIAL_ROUTES[special_route] || "Rota especial"
  end

  def van_plate?
    plate.perfil == "VAN" || plate.tipo == "Van"
  end

  def reason_label
    {
      "maintenance" => "Manutenção",
      "breakdown" => "Quebra",
      "accident" => "Acidente",
      "document" => "Documentação",
      "other" => "Outro"
    }[reason] || "Sem defeito informado"
  end

  private

  def special_route_is_valid
    return if special_route.blank?
    return if FleetAvailability::SPECIAL_ROUTES.key?(special_route)

    errors.add(:special_route, "inválida")
  end

  def special_route_is_active
    return if special_route.blank?
    return if fleet_availability.special_route_quantity(special_route).positive?

    errors.add(:special_route, "não foi dimensionada nessa disponibilidade")
  end

  def special_route_status_has_route
    return unless status == "special_route" && special_route.blank?

    errors.add(:special_route, "precisa ser informada")
  end

  def special_route_quantity_is_available
    return unless status == "special_route" && special_route.present?

    quantity = fleet_availability.special_route_quantity(special_route)
    used_quantity = fleet_availability
                    .fleet_availability_items
                    .where(status: FleetAvailabilityItem.statuses[:special_route],
                           special_route: special_route)
                    .where.not(id: id)
                    .count

    return if used_quantity < quantity

    errors.add(:special_route, "já atingiu a quantidade dimensionada")
  end

  def van_route_requires_van_plate
    return unless status == "special_route" && special_route == "van"
    return if van_plate?

    errors.add(:plate, "precisa ser VAN para a rota Van")
  end

  def available_position_is_dimensioned
    return unless available?
    return if position.to_i < fleet_availability.agreed_quantity.to_i

    errors.add(:position, "precisa estar dentro da disponibilidade dimensionada")
  end
end
