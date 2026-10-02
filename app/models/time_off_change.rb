class TimeOffChange < ApplicationRecord
  belongs_to :time_off_schedule
  belongs_to :time_off_membership, optional: true
  belongs_to :user, optional: true
end
