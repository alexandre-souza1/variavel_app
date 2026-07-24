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
end
