class TimeOffSchedule < ApplicationRecord
  ROTATING_GROUPS = %w[A B C D E F].freeze
  GROUPS = (ROTATING_GROUPS + ['FIXO']).freeze
  WEEKDAYS = { 'Segunda-feira' => 1, 'Terça-feira' => 2, 'Quarta-feira' => 3, 'Quinta-feira' => 4, 'Sexta-feira' => 5, 'Sábado' => 6 }.freeze
  STATUSES = { 'working' => 'Em escala', 'off' => 'Folga', 'unavailable' => 'Indisponível', 'vacation' => 'Férias', 'dsr' => 'DSR', 'pending' => 'Folga fixa a definir' }.freeze

  has_many :time_off_memberships, dependent: :restrict_with_exception
  has_many :time_off_changes, dependent: :restrict_with_exception
  has_many :time_off_daily_plans, dependent: :restrict_with_exception
  has_many :time_off_vacations, dependent: :restrict_with_exception
  validates :name, :starts_on, :ends_on, :rotation_anchor, presence: true
  validate :valid_period

  def covers?(date)
    date >= starts_on && (recurring? || date <= ends_on)
  end

  # Each week moves the weekday of rest back one day. Sundays never
  # participate in the six-group rotation. Anchor: A on Monday 28/09/2026.
  def off_group_on(date)
    return unless covers?(date) && !date.sunday?
    week = (date - rotation_anchor).to_i.div(7)
    ROTATING_GROUPS[(date.cwday - 1 - week) % ROTATING_GROUPS.length]
  end

  def base_status(membership, date)
    return unless covers?(date) && membership.covers?(date)
    return 'dsr' if date.sunday?
    if membership.group_code == 'FIXO'
      return 'pending' unless membership.fixed_weekday
      return date.cwday == membership.fixed_weekday ? 'off' : 'working'
    end
    off_group_on(date) == membership.group_code ? 'off' : 'working'
  end

  private

  def valid_period
    errors.add(:ends_on, 'deve ser posterior ao início') if starts_on && ends_on && ends_on < starts_on
    errors.add(:rotation_anchor, 'deve ser uma segunda-feira') if rotation_anchor && !rotation_anchor.monday?
  end
end
