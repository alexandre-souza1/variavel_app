require "set"

class Routine < ApplicationRecord
  WEEKDAY_LABELS = {
    0 => "Domingo",
    1 => "Segunda-feira",
    2 => "Terça-feira",
    3 => "Quarta-feira",
    4 => "Quinta-feira",
    5 => "Sexta-feira",
    6 => "Sábado"
  }.freeze

  belongs_to :routine_template
  belongs_to :action_plan, optional: true

  delegate :sector, to: :routine_template, allow_nil: true

  belongs_to :created_by,
             class_name: "User"

  has_many :routine_values,
           dependent: :destroy

  has_many :routine_activities,
           dependent: :destroy

  scope :visible_to, lambda { |user|
    return all if user&.admin?

    joins(:routine_template).where(action_plan_id: nil, routine_templates: { sector: user&.sector })
      .or(joins(:routine_template).where(action_plan_id: ActionPlan.visible_to(user).select(:id)))
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

  TASK_GENERATION_LABELS = {
    "commented_deviation" => "Comentário em indicador fora da meta",
    "deviation" => "Preenchimento fora da meta"
  }.freeze

  enum :task_generation_mode, { commented_deviation: 0, deviation: 1 }, prefix: :task_generation

  def task_generation_label
    TASK_GENERATION_LABELS.fetch(task_generation_mode)
  end

  validates :period_start,
            presence: true

  validates :period_end,
            presence: true

  validates :routine_template_id, uniqueness: {
    scope: %i[action_plan_id period_start period_end],
    message: "já possui um GEROT neste período e plano"
  }
  validate :template_matches_plan_sector
  validate :template_belongs_to_plan

  validates :weekly_reference_weekday,
            inclusion: { in: 0..6 },
            allow_nil: true

  validates :monthly_reference_day,
            inclusion: { in: 1..31 },
            allow_nil: true

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
      reference_dates_for(indicator).each do |date|
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

  def reference_dates_for(indicator)
    indicator.reference_dates_between(
      period_start,
      period_end,
      weekly_reference_weekday: weekly_reference_weekday,
      monthly_reference_day: monthly_reference_day
    )
  end

  def manageable_by?(user)
    user.present? && (user.admin? || created_by_id == user.id || action_plan&.manageable_by?(user))
  end

  def generated_tasks
    Task.where(routine_value_id: routine_values.select(:id))
  end

  private

  def template_belongs_to_plan
    return if routine_template&.action_plan_id == action_plan_id

    errors.add(:routine_template, "deve ser o modelo exclusivo deste plano; GEROTs independentes usam modelos independentes")
  end

  def template_matches_plan_sector
    return if action_plan.blank? || action_plan.sector == routine_template&.sector

    errors.add(:routine_template, "deve ser do mesmo setor do plano de ação")
  end

  def period_end_after_start
    return if period_end.blank? || period_start.blank?

    return if period_end >= period_start

    errors.add(:period_end, "deve ser maior que a data inicial")
  end
end
