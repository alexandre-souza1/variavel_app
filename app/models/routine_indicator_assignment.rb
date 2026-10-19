class RoutineIndicatorAssignment < ApplicationRecord
  belongs_to :routine_indicator
  belongs_to :user

  validates :user_id, uniqueness: { scope: :routine_indicator_id }
end
