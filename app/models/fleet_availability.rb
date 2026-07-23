class FleetAvailability < ApplicationRecord
  self.lock_optimistically = false

  SPECIAL_ROUTES = {
    "vespertina" => "Vespertina",
    "van" => "Van",
    "as" => "AS"
  }.freeze

  attr_accessor :copy_previous_day

  belongs_to :user
  belongs_to :locked_by,
             class_name: "User",
             optional: true

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
            uniqueness: true
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

  def sync_dimensioning!
    dimensioning = self.class.dimensioning_period_for(date)

    return unless dimensioning
    route_quantity = dimensioning.route_quantity.to_i

    if agreed_quantity.to_i != route_quantity ||
       special_routes != dimensioning.special_routes
      self.class
        .where(id: id)
        .update_all(
          self.class.sanitize_sql_array(
            [
              "agreed_quantity = ?, special_routes = ?, updated_at = ?",
              route_quantity,
              dimensioning.special_routes.to_json,
              Time.current
            ]
          )
        )

      self.agreed_quantity = route_quantity
      self.special_routes = dimensioning.special_routes
    end

    fleet_availability_items
      .available
      .where("position >= ?", route_quantity)
      .update_all(
        status: FleetAvailabilityItem.statuses[:exchange],
        reason: nil,
        special_route: nil,
        updated_at: Time.current
      )
  end

  def locked?
    self.class.locking_enabled? && locked_at.present?
  end

  def editable_by?(user)
    return false if user.blank? || locked?

    user == self.user || user.sector_fleet?
  end

  def lock_availability!(user)
    return false unless self.class.locking_enabled?

    self.class.update_lock_columns(
      id,
      locked_at: Time.current,
      locked_by_id: user.id
    )
    reload
  end

  def unlock_availability!
    return false unless self.class.locking_enabled?

    self.class.update_lock_columns(
      id,
      locked_at: nil,
      locked_by_id: nil
    )
    reload
  end

  def destroy_without_lock_version!
    self.class.transaction do
      item_ids = fleet_availability_items.select(:id)

      FleetAvailabilityChange
        .where(fleet_availability_item_id: item_ids)
        .delete_all
      FleetAvailabilityItem
        .where(fleet_availability_id: id)
        .delete_all
      self.class
        .where(id: id)
        .delete_all
    end
  end

  def self.locking_enabled?
    columns_hash.key?("locked_at")
  end

  def self.update_lock_columns(id, locked_at:, locked_by_id:)
    sanitized_sql = sanitize_sql_array(
      [
        <<~SQL.squish,
          locked_at = ?,
          locked_by_id = ?,
          updated_at = ?
        SQL
        locked_at,
        locked_by_id,
        Time.current
      ]
    )

    where(id: id).update_all(sanitized_sql)
  end

  def self.auto_lock_expired!
    return 0 unless locking_enabled?

    sanitized_sql = sanitize_sql_array(
      [
        <<~SQL.squish,
          locked_at = ?,
          locked_by_id = NULL,
          updated_at = ?
        SQL
        Time.current,
        Time.current
      ]
    )

    where(locked_at: nil)
      .where("created_at <= ?", 24.hours.ago)
      .update_all(sanitized_sql)
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
