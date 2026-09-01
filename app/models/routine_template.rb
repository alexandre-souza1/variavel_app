class RoutineTemplate < ApplicationRecord
  has_many :routine_categories,
           -> { order(:position) },
           dependent: :destroy

  has_many :routines,
           dependent: :restrict_with_error

  enum :sector, User.sectors, prefix: true

  validates :name,
            presence: true,
            uniqueness: true

  validates :sector,
            presence: true

  scope :active, -> { where(active: true) }
  scope :visible_to, lambda { |user|
    return all if user&.admin?

    where(sector: user&.sector)
  }
end
