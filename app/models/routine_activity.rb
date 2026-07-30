class RoutineActivity < ApplicationRecord
  belongs_to :routine
  belongs_to :user

  belongs_to :routine_value,
             optional: true

  enum :activity_type, {
    value_changed: 0
  }

  validates :activity_type,
            presence: true

  after_create_commit :broadcast_activity

  private

  def broadcast_activity
    broadcast_prepend_to(
      [routine, :activities],
      target: "routine-activities-list",
      partial: "routine_activities/activity",
      locals: {
        activity: self
      }
    )
  end
end
