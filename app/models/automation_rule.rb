class AutomationRule < ApplicationRecord
  SCHEDULES = { "Somente manual" => "manual", "A cada hora" => "hourly", "Diariamente" => "daily", "Semanalmente" => "weekly", "Mensalmente" => "monthly" }.freeze
  CONDITIONS = { "Sempre" => "always", "Maior que" => "gt", "Maior ou igual a" => "gte", "Menor que" => "lt", "Menor ou igual a" => "lte", "Igual a" => "eq" }.freeze

  belongs_to :user
  has_many :automation_runs, dependent: :restrict_with_error
  has_many :routine_values, dependent: :nullify

  scope :visible_to, ->(user) { user&.admin? ? all : where(user_id: user&.id) }
  scope :due, -> { where(enabled: true).where("next_run_at <= ?", Time.current) }

  validates :name, presence: true, length: { maximum: 120 }
  validates :description, length: { maximum: 2000 }
  validates :schedule, inclusion: { in: SCHEDULES.values }
  validates :execution_hour, inclusion: { in: 0..23 }
  validates :weekday, inclusion: { in: 0..6 }
  validates :month_day, inclusion: { in: 1..31 }
  validates :condition_operator, inclusion: { in: CONDITIONS.values }
  validates :condition_value, numericality: true, unless: -> { condition_operator == "always" }
  validate :supported_configuration
  validate :one_active_writer
  before_save :refresh_schedule

  def condition_met?(value)
    case condition_operator
    when "always" then true
    when "gt" then value.to_d > condition_value
    when "gte" then value.to_d >= condition_value
    when "lt" then value.to_d < condition_value
    when "lte" then value.to_d <= condition_value
    when "eq" then value.to_d == condition_value
    end
  end

  def next_occurrence(after: Time.current)
    return if !enabled? || schedule == "manual"
    return after.beginning_of_hour + 1.hour if schedule == "hourly"
    (after.to_date..after.to_date + 370).each do |date|
      next if schedule == "weekly" && date.wday != weekday
      next if schedule == "monthly" && date.day != [month_day, date.end_of_month.day].min
      candidate = date.in_time_zone.change(hour: execution_hour)
      return candidate if candidate > after
    end
  end

  private

  def supported_configuration
    Automations::Configuration.validate!(self)
  rescue Automations::Invalid => error
    errors.add(:base, error.message)
  end

  def one_active_writer
    return unless enabled? && action_key == "update_indicator" && action_config.is_a?(Hash)
    conflict = self.class.where(enabled: true, action_key: action_key).where.not(id: id)
      .where("action_config->>'routine_template_id' = ? AND action_config->>'routine_indicator_id' = ?",
        action_config["routine_template_id"].to_s, action_config["routine_indicator_id"].to_s).exists?
    errors.add(:base, "Este indicador já possui outra automação ativa.") if conflict
  end

  def refresh_schedule
    fields = %w[enabled schedule execution_hour weekday month_day]
    self.next_run_at = next_occurrence if new_record? || (changed & fields).any?
  end
end
