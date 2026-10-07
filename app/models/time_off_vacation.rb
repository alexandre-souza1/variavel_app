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
    # Vacations belong to the person and may extend beyond the schedule or
    # group assignment. Availability applies them only to days in the scale.
    unless time_off_membership.time_off_schedule_id == time_off_schedule_id
      errors.add(:base, 'Colaborador deve pertencer à escala selecionada')
    end
  end

  def no_overlap
    return unless starts_on && ends_on && time_off_membership && time_off_schedule && !cancelled_at
    others = time_off_schedule.time_off_vacations.active.during(starts_on, ends_on).where.not(id: id)
      .includes(time_off_membership: [:driver, :ajudante])
    errors.add(:base, 'Já há férias cadastradas para este colaborador no período') if others.any? { |v| v.person_key == person_key }
  end
end
