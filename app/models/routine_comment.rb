class RoutineComment < ApplicationRecord
  belongs_to :routine_value

  belongs_to :user

  has_one :generated_task, class_name: "Task", dependent: :nullify

  validates :body,
            presence: true
end
