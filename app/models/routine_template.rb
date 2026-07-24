class RoutineTemplate < ApplicationRecord
  has_many :routine_categories,
           -> { order(:position) },
           dependent: :destroy

  has_many :routines,
           dependent: :restrict_with_error

  validates :name,
            presence: true,
            uniqueness: true

  scope :active, -> { where(active: true) }
end
