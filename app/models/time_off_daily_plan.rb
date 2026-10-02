class TimeOffDailyPlan < ApplicationRecord
  belongs_to :time_off_schedule
  validates :date, presence: true, uniqueness: { scope: :time_off_schedule_id }
  validates :dimensioning_signature, presence: true
  validates :reason, presence: true, length: { maximum: 500 }
end
