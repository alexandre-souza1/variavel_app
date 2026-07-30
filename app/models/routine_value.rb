class RoutineValue < ApplicationRecord
  belongs_to :routine

  belongs_to :routine_indicator

  belongs_to :updated_by,
             class_name: "User",
             optional: true

  has_many :routine_comments,
           dependent: :destroy

  has_many :routine_activities,
         dependent: :destroy

  validates :reference_date,
            presence: true

  after_update_commit :broadcast_collaboration_update,
                    if: :saved_change_to_value?

  private

  def broadcast_collaboration_update
    broadcast_render_to(
      [routine, :collaboration],
      partial: "routine_values/collaboration_update",
      locals: {
        routine_value: self
      }
    )
  end
end
