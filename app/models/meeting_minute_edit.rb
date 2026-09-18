class MeetingMinuteEdit < ApplicationRecord
  belongs_to :meeting_minute
  belongs_to :user

  validates :changes_snapshot, presence: true
end
