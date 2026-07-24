class RoutineComment < ApplicationRecord
  belongs_to :routine_value

  belongs_to :user

  validates :body,
            presence: true
end
