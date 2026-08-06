class RoutineIndicatorTarget < ApplicationRecord
  belongs_to :routine_indicator

  validates :goal, presence: true
  validates :starts_at, presence: true

  validate :goal_matches_indicator_type
  validate :ends_at_not_before_starts_at

  private

  def goal_matches_indicator_type
    return if goal.blank?

    case routine_indicator.value_type
    when "integer"
      unless goal.match?(/\A-?\d+\z/)
        errors.add(:goal, "deve ser um número inteiro")
      end

    when "decimal", "percentage", "currency"
      unless goal.match?(/\A-?\d+(?:\.\d+)?\z/)
        errors.add(:goal, "deve ser um número válido")
      end

    when "date"
      validate_date_goal

    when "time"
      unless goal.match?(/\A(?:[01]\d|2[0-3]):[0-5]\d\z/)
        errors.add(:goal, "deve ser um horário válido")
      end

    when "boolean"
      unless goal.in?(%w[true false 1 0])
        errors.add(:goal, "deve ser Sim ou Não")
      end
    end
  end

  def validate_date_goal
    Date.iso8601(goal)
  rescue Date::Error
    errors.add(:goal, "deve ser uma data válida")
  end

  def ends_at_not_before_starts_at
    return if starts_at.blank?
    return if ends_at.blank?
    return if ends_at >= starts_at

    errors.add(
      :ends_at,
      "não pode ser anterior à data inicial"
    )
  end
end
