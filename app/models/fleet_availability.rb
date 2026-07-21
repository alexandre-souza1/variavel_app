class FleetAvailability < ApplicationRecord
  SPECIAL_ROUTES = {
    "vespertina" => "Vespertina",
    "van" => "Van",
    "as" => "AS"
  }.freeze

  attr_accessor :copy_previous_day

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
  validate :special_routes_are_valid

  def available_count
    fleet_availability_items.available.count
  end

  def exchange_count
    fleet_availability_items.exchange.count
  end

  def deposit_count
    exchange_count
  end

  def unavailable_count
    fleet_availability_items.unavailable.count
  end

  def coverage_percentage
    return 0 if agreed_quantity.zero?

    ((available_count.to_f / agreed_quantity) * 100).round
  end

  def self.dimensioning_period_for(date)
    FleetDimensioning.for_date(date)
  end

  def self.default_dimensioning_quantity_for(date)
    dimensioning = dimensioning_period_for(date)

    return 0 unless dimensioning

    dimensioning.route_quantity.to_i
  end

  def self.default_agreed_quantity_for(date)
    default_dimensioning_quantity_for(date)
  end

  def self.default_special_routes_for(date)
    dimensioning = dimensioning_period_for(date)

    return {} unless dimensioning

    dimensioning.special_routes
  end

  def special_routes=(routes)
    super(normalize_special_routes(routes))
  end

  def special_routes
    normalize_special_routes(super)
  end

  def active_special_routes
    special_routes.select { |_route, quantity| quantity.positive? }
  end

  def special_route_quantity(route)
    special_routes[route].to_i
  end

  def special_route_labels
    active_special_routes.keys.map { |route| SPECIAL_ROUTES[route] }.compact
  end

  private

  def normalize_special_routes(routes)
    normalized_routes =
      case routes
      when Hash
        routes.to_h
      when ->(value) { value.respond_to?(:to_unsafe_h) }
        routes.to_unsafe_h
      else
        Array(routes).reject(&:blank?).index_with(1)
      end

    SPECIAL_ROUTES.each_key.with_object({}) do |route, normalized|
      quantity = normalized_routes[route].to_i
      normalized[route] = quantity if quantity.positive?
    end
  end

  def special_routes_are_valid
    invalid_routes = special_routes.keys - SPECIAL_ROUTES.keys

    return if invalid_routes.empty?

    errors.add(:special_routes, "possui rotas inválidas")
  end
  
end
