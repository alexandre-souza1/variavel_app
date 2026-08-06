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

  validate :value_matches_indicator_type

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

  def value_matches_indicator_type
    return if value.blank?

    case routine_indicator.value_type
    when "integer"
      errors.add(:value, "deve ser um número inteiro") unless integer_value?

    when "decimal", "percentage", "currency"
      errors.add(:value, "deve ser um número válido") unless decimal_value?

    when "date"
      errors.add(:value, "deve ser uma data válida") unless date_value?

    when "time"
      errors.add(:value, "deve ser um horário válido") unless time_value?

    when "boolean"
      errors.add(:value, "deve ser Sim ou Não") unless boolean_value?
    end
  end

  def integer_value?
    value.match?(/\A-?\d+\z/)
  end

  def decimal_value?
    value.match?(/\A-?\d+(?:\.\d+)?\z/)
  end

  def date_value?
    Date.iso8601(value)
    true
  rescue Date::Error
    false
  end

  def time_value?
    value.match?(/\A(?:[01]\d|2[0-3]):[0-5]\d\z/)
  end

  def boolean_value?
    value.in?(%w[true false 1 0])
  end
end
