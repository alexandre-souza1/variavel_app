class AddOriginalSummaryToMeetingMinutes < ActiveRecord::Migration[7.1]
  def change
    add_column :meeting_minutes, :original_summary, :text

    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE meeting_minutes
          SET original_summary = summary
          WHERE original_summary IS NULL
        SQL
      end
    end
  end
end
