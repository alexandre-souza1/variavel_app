class RoutineIndicator < ApplicationRecord
  belongs_to :routine_category

  has_many :routine_indicator_targets,
           dependent: :destroy

  has_many :routine_values,
           dependent: :restrict_with_error

  enum :calculation_type, {
    manual_calculation: 0,
    ranged: 1,
    plus: 2,
    last_value: 3,
    minimal: 4,
    maximal: 5
  }

  enum :value_type, {
    integer: 0,
    decimal: 1,
    percentage: 2,
    currency: 3,
    boolean: 4,
    text: 5,
    date: 6,
    time: 7
  }

  enum :goal_direction, {
    greater_or_equal: 0,
    less_or_equal: 1
  }

  validates :name, presence: true
  validates :position, presence: true

  scope :active, -> { where(active: true) }

  def calculation_type_label
    {
      "manual_calculation" => "Manual",
      "ranged" => "Média",
      "plus" => "Soma",
      "last_value" => "Último valor",
      "minimal" => "Menor valor",
      "maximal" => "Maior valor"
    }[calculation_type]
  end

  def value_type_label
    {
      "integer" => "Número",
      "decimal" => "Decimal",
      "percentage" => "%",
      "currency" => "Moeda",
      "boolean" => "Sim/Não",
      "text" => "Texto",
      "date" => "Data",
      "time" => "Hora"
    }[value_type]
  end

  def target_for(date)
    routine_indicator_targets
      .where("starts_at <= ?", date)
      .where("ends_at IS NULL OR ends_at >= ?", date)
      .order(starts_at: :desc)
      .first
  end

    VALUE_TYPE_LABELS = {
    "integer"   => "Número",
    "decimal"   => "Decimal",
    "percentage"=> "%",
    "currency"  => "Moeda",
    "boolean"   => "Sim/Não",
    "text"      => "Texto",
    "date"      => "Data",
    "time"      => "Hora"
  }.freeze

  CALCULATION_TYPE_LABELS = {
    "manual_calculation" => "Manual",
    "ranged"             => "Média",
    "plus"               => "Soma",
    "last_value"         => "Último valor",
    "minimal"            => "Menor valor",
    "maximal"            => "Maior valor"
  }.freeze

  GOAL_DIRECTION_LABELS = {
    "greater_or_equal" => "Maior ou igual",
    "less_or_equal"    => "Menor ou igual"
  }.freeze
end
