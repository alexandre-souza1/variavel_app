class TimeOffOverride < ApplicationRecord
  belongs_to :time_off_membership
  validates :date, presence: true, uniqueness: { scope: :time_off_membership_id }
  validates :status, inclusion: { in: %w[working off unavailable] }
  validates :reason, presence: true, length: { maximum: 500 }
  validate :valid_day

  private

  def valid_day
    return unless date && time_off_membership
    schedule = time_off_membership.time_off_schedule
    errors.add(:date, 'está fora da vigência da escala ou do grupo') unless schedule.covers?(date) && time_off_membership.covers?(date)
    errors.add(:date, 'é domingo: DSR para todos') if date.sunday?
  end
end
