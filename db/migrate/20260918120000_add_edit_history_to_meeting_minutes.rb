class AddEditHistoryToMeetingMinutes < ActiveRecord::Migration[7.1]
  def change
    add_reference :meeting_minutes, :collaborator,
      foreign_key: { to_table: :users },
      null: true
    add_column :meeting_minutes, :original_decisions, :jsonb, null: false, default: []
    add_column :meeting_minutes, :original_pending_items, :jsonb, null: false, default: []

    reversible do |direction|
      direction.up do
        execute <<~SQL
          UPDATE meeting_minutes
          SET original_decisions = decisions,
              original_pending_items = pending_items
          WHERE original_decisions = '[]'::jsonb
            AND original_pending_items = '[]'::jsonb
        SQL
      end
    end

    create_table :meeting_minute_edits do |t|
      t.references :meeting_minute, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.jsonb :changes_snapshot, null: false, default: {}
      t.timestamps
    end
  end
end
