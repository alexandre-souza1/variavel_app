class RoutineIndicatorLabel < ApplicationRecord
  belongs_to :routine_indicator
  belongs_to :label

  validates :label_id, uniqueness: { scope: :routine_indicator_id }
  validate :label_matches_indicator_plan

  private

  def label_matches_indicator_plan
    return unless routine_indicator && label
    return if label.action_plan_id == routine_indicator.action_plan&.id

    errors.add(:label, "deve pertencer ao plano do indicador")
  end
end
