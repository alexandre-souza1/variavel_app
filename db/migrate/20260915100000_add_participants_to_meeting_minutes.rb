class AddParticipantsToMeetingMinutes < ActiveRecord::Migration[7.1]
  def change
    add_column :meeting_minutes, :participants, :jsonb, null: false, default: []
  end
end
