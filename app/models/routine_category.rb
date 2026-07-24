class RoutineCategory < ApplicationRecord
  belongs_to :routine_template

  has_many :routine_indicators,
           -> { order(:position) },
           dependent: :destroy

  validates :name,
            presence: true

  validates :position,
            presence: true
end
