class FleetDimensioning < ApplicationRecord
  STANDARD_PLATE_SLOTS = 18

  has_many :fleet_dimensioning_standard_plates,
           -> { order(:position) },
           dependent: :destroy,
           inverse_of: :fleet_dimensioning
  has_many :standard_plates,
           through: :fleet_dimensioning_standard_plates,
           source: :plate

  accepts_nested_attributes_for :fleet_dimensioning_standard_plates,
                                allow_destroy: true,
                                reject_if: :new_standard_plate_blank?

  validates :label,
            :start_date,
            :end_date,
            presence: true
  validates :label, uniqueness: true
  validates :route_quantity,
            :van_quantity,
            :vespertina_quantity,
            :as_quantity,
            numericality: {
              greater_than_or_equal_to: 0
            }
  validate :start_before_end
  validate :period_does_not_overlap

  scope :recent, -> { order(start_date: :desc) }

  def self.for_date(date)
    return if date.blank?

    parsed_date = date.to_date

    where("start_date <= ? AND end_date >= ?", parsed_date, parsed_date)
      .first
  end

  def special_routes
    {
      "vespertina" => vespertina_quantity.to_i,
      "van" => van_quantity.to_i,
      "as" => as_quantity.to_i
    }.select { |_route, quantity| quantity.positive? }
  end

  def standard_plate_by_position
    fleet_dimensioning_standard_plates
      .includes(:plate)
      .index_by(&:position)
  end

  def build_standard_plate_slots(quantity = nil)
    slot_quantity = [quantity || route_quantity.to_i, STANDARD_PLATE_SLOTS].max

    slot_quantity.times do |position|
      next if fleet_dimensioning_standard_plates.any? { |item| item.position == position }

      fleet_dimensioning_standard_plates.build(position: position)
    end
  end

  private

  def new_standard_plate_blank?(attributes)
    attributes["id"].blank? && attributes["plate_id"].blank?
  end

  def start_before_end
    return unless start_date && end_date && start_date > end_date

    errors.add(:start_date, "deve ser anterior à data final")
  end

  def period_does_not_overlap
    return unless start_date && end_date

    overlapping_periods = FleetDimensioning
                          .where.not(id: id)
                          .where("start_date <= ? AND end_date >= ?",
                                 end_date,
                                 start_date)

    return unless overlapping_periods.exists?

    errors.add(:base, "já existe dimensionamento cadastrado nesse período")
  end
end
