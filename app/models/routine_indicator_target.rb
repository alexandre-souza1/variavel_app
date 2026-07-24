class RoutineIndicatorTarget < ApplicationRecord
  belongs_to :routine_indicator

  validates :goal,
            presence: true

  validates :starts_at,
            presence: true

  validate :ends_at_after_starts_at

  private

  def ends_at_after_starts_at
    return if ends_at.blank?

    return if ends_at >= starts_at

    errors.add(:ends_at, "deve ser maior que a data inicial")
  end
end
