class FleetAvailability < ApplicationRecord
  belongs_to :user

  has_many :fleet_availability_items,
           -> { order(:position) },
           dependent: :destroy,
           inverse_of: :fleet_availability
  has_many :plates,
           through: :fleet_availability_items

  accepts_nested_attributes_for :fleet_availability_items
  scope :recent, -> { order(date: :desc) }

  validates :date,
            presence: true,
            uniqueness: {
              scope: :user_id
            }
  validates :agreed_quantity,
            numericality: {
              greater_than_or_equal_to: 0
            }

  def available_count
    fleet_availability_items.available.count
  end

  def exchange_count
    fleet_availability_items.exchange.count
  end

  def unavailable_count
    fleet_availability_items.unavailable.count
  end

  def coverage_percentage
    return 0 if agreed_quantity.zero?

    ((available_count.to_f / agreed_quantity) * 100).round
  end
  
end
