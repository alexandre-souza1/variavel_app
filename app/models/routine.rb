require "set"

class Routine < ApplicationRecord
  belongs_to :routine_template

  delegate :sector, to: :routine_template, allow_nil: true

  belongs_to :created_by,
             class_name: "User"

  has_many :routine_values,
           dependent: :destroy

  has_many :routine_activities,
           dependent: :destroy

  scope :visible_to, lambda { |user|
    return all if user&.admin?

    joins(:routine_template).where(routine_templates: { sector: user&.sector })
  }

  def selected_indicator_ids
    value = self[:selected_indicator_ids]
    return default_selected_indicator_ids if value.blank?

    Array(value).map(&:to_i)
  end

  def selected_indicators
    return default_selected_indicators if selected_indicator_ids.blank?

    RoutineIndicator
      .includes(:routine_category)
      .where(id: selected_indicator_ids)
      .order("routine_categories.position ASC, routine_indicators.position ASC")
      .joins(:routine_category)
  end

  def default_selected_indicator_ids
    routine_template
      .routine_categories
      .includes(:routine_indicators)
      .flat_map { |category| category.routine_indicators.map(&:id) }
  end

  def default_selected_indicators
    RoutineIndicator
      .includes(:routine_category)
      .where(id: default_selected_indicator_ids)
      .order("routine_categories.position ASC, routine_indicators.position ASC")
      .joins(:routine_category)
  end

  enum :status, {
    open: 0,
    closed: 1,
    archived: 2
  }

  validates :period_start,
            presence: true

  validates :period_end,
            presence: true

  validate :period_end_after_start

  def ensure_expected_values!(indicators: nil)
    indicators ||= routine_template
      .routine_categories
      .includes(:routine_indicators)
      .flat_map(&:routine_indicators)

    existing_keys = routine_values
      .where(routine_indicator_id: indicators.map(&:id))
      .pluck(:routine_indicator_id, :reference_date)
      .to_set

    now = Time.current
    rows = []

    indicators.each do |indicator|
      indicator.reference_dates_between(period_start, period_end).each do |date|
        key = [indicator.id, date]
        next if existing_keys.include?(key)

        rows << {
          routine_id: id,
          routine_indicator_id: indicator.id,
          reference_date: date,
          created_at: now,
          updated_at: now
        }
      end
    end

    RoutineValue.insert_all(
      rows,
      unique_by: :idx_unique_routine_value
    ) if rows.any?
  end

  private

  def period_end_after_start
    return if period_end.blank? || period_start.blank?

    return if period_end >= period_start

    errors.add(:period_end, "deve ser maior que a data inicial")
  end
end
