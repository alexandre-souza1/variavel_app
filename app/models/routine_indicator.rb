class RoutineIndicator < ApplicationRecord
  belongs_to :routine_category

  has_many :routine_indicator_targets,
           dependent: :destroy

  has_many :routine_values,
           dependent: :restrict_with_error

  enum :calculation_type, {
    manual_calculation: 0,
    ranged: 1,
    plus: 2,
    last_value: 3,
    minimal: 4,
    maximal: 5
  }

  enum :value_type, {
    integer: 0,
    decimal: 1,
    percentage: 2,
    currency: 3,
    boolean: 4,
    text: 5,
    date: 6,
    time: 7,
    duration: 8
  }

  enum :goal_direction, {
    greater_or_equal: 0,
    less_or_equal: 1
  }

  enum :response_frequency, {
    daily: 0,
    weekly: 1,
    monthly: 2
  }

  validates :name, presence: true
  validates :position, presence: true

  scope :active, -> { where(active: true) }

  def reference_dates_between(period_start, period_end)
    return [] if period_start.blank? || period_end.blank?

    return monthly_reference_dates_between(
      period_start,
      period_end
    ) if monthly?

    return weekly_reference_dates_between(
      period_start,
      period_end
    ) if weekly?

    dates = []
    current_date = period_start.to_date
    last_date = period_end.to_date

    while current_date <= last_date
      dates << current_date

      current_date += 1.day
    end

    dates
  end

  def expects_value_on?(date, period_start, period_end)
    reference_dates_between(period_start, period_end).include?(
      date.to_date
    )
  end

  def calculation_type_label
    {
      "manual_calculation" => "Manual",
      "ranged" => "Média",
      "plus" => "Soma",
      "last_value" => "Último valor",
      "minimal" => "Menor valor",
      "maximal" => "Maior valor"
    }[calculation_type]
  end

  def value_type_label
    {
      "integer" => "Número",
      "decimal" => "Decimal",
      "percentage" => "%",
      "currency" => "Moeda",
      "boolean" => "Sim/Não",
      "text" => "Texto",
      "date" => "Data",
      "time" => "Hora",
      "duration" => "Duração"
    }[value_type]
  end

  def target_for(date)
    if routine_indicator_targets.loaded?
      return routine_indicator_targets
        .select do |target|
          target.starts_at <= date &&
            (target.ends_at.blank? || target.ends_at >= date)
        end
        .sort_by do |target|
          [
            -target.starts_at.to_time.to_i,
            target.ends_at.nil? ? 1 : 0,
            target.ends_at || Date.new(9999, 12, 31)
          ]
        end
        .first
    end

    routine_indicator_targets
      .where("starts_at <= ?", date)
      .where("ends_at IS NULL OR ends_at >= ?", date)
      .order(starts_at: :desc)
      .order(Arel.sql("ends_at IS NULL ASC"))
      .order(ends_at: :asc)
      .first
  end

    VALUE_TYPE_LABELS = {
    "integer"   => "Número",
    "decimal"   => "Decimal",
    "percentage"=> "%",
    "currency"  => "Moeda",
    "boolean"   => "Sim/Não",
    "text"      => "Texto",
    "date"      => "Data",
    "time"      => "Hora",
    "duration"  => "Duração"
  }.freeze

  CALCULATION_TYPE_LABELS = {
    "manual_calculation" => "Manual",
    "ranged"             => "Média",
    "plus"               => "Soma",
    "last_value"         => "Último valor",
    "minimal"            => "Menor valor",
    "maximal"            => "Maior valor"
  }.freeze

  GOAL_DIRECTION_LABELS = {
    "greater_or_equal" => "Maior ou igual",
    "less_or_equal"    => "Menor ou igual"
  }.freeze

  RESPONSE_FREQUENCY_LABELS = {
    "daily"   => "Diário",
    "weekly"  => "Semanal",
    "monthly" => "Mensal"
  }.freeze

  private

  def weekly_reference_dates_between(period_start, period_end)
    dates = []
    current_date = period_start.to_date
    last_date = period_end.to_date

    current_date += 1.day until current_date.monday?

    while current_date <= last_date
      dates << current_date
      current_date += 1.week
    end

    dates
  end

  def monthly_reference_dates_between(period_start, period_end)
    dates = []
    first_date = period_start.to_date
    last_date = period_end.to_date
    current_date = first_date.beginning_of_month

    while current_date <= last_date
      month_end = current_date.end_of_month
      dates << month_end if month_end.between?(first_date, last_date)

      current_date = current_date.next_month
    end

    dates
  end
end
