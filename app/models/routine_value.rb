class RoutineValue < ApplicationRecord
  belongs_to :routine

  belongs_to :routine_indicator

  belongs_to :updated_by,
             class_name: "User",
             optional: true

  has_many :routine_comments,
           dependent: :destroy

  validates :reference_date,
            presence: true
end
