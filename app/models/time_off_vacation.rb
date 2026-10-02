class TimeOffVacation < ApplicationRecord
  belongs_to :time_off_schedule
  belongs_to :time_off_membership
  validates :starts_on, :ends_on, presence: true
  validates :reason, presence: true, length: { maximum: 500 }
  validate :valid_period
  validate :no_overlap

  scope :active, -> { where(cancelled_at: nil) }
  scope :during, ->(first, last) { where('starts_on <= ? AND ends_on >= ?', last, first) }

  def covers?(date)
    !cancelled_at && starts_on <= date && ends_on >= date
  end

  def person_key
    time_off_membership.person_key
  end

  private

  def valid_period
    return if cancelled_at
    return unless starts_on && ends_on && time_off_membership && time_off_schedule
    errors.add(:ends_on, 'deve ser igual ou posterior ao início') if ends_on < starts_on
    unless time_off_membership.time_off_schedule_id == time_off_schedule_id && time_off_schedule.covers?(starts_on) && time_off_schedule.covers?(ends_on)
      errors.add(:base, 'Período fora da vigência da escala')
    end
    members = time_off_schedule.time_off_memberships.during(starts_on, ends_on).includes(:driver, :ajudante).select { |m| m.person_key == person_key }
    cursor = starts_on
    members.sort_by(&:starts_on).each do |member|
      next if member.ends_on && member.ends_on < cursor
      break if member.starts_on > cursor
      cursor = [cursor, (member.ends_on || ends_on) + 1].max
    end
    errors.add(:base, 'Colaborador deve pertencer à escala durante todo o período de férias') if cursor <= ends_on
  end

  def no_overlap
    return unless starts_on && ends_on && time_off_membership && time_off_schedule && !cancelled_at
    others = time_off_schedule.time_off_vacations.active.during(starts_on, ends_on).where.not(id: id)
      .includes(time_off_membership: [:driver, :ajudante])
    errors.add(:base, 'Já há férias cadastradas para este colaborador no período') if others.any? { |v| v.person_key == person_key }
  end
end
