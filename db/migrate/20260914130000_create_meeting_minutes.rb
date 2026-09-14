class CreateMeetingMinutes < ActiveRecord::Migration[7.1]
  def change
    create_table :meeting_minutes do |t|
      t.references :action_plan, null: false, foreign_key: true
      t.references :creator, null: false, foreign_key: { to_table: :users }
      t.string :title, null: false
      t.date :meeting_date, null: false
      t.string :status, null: false, default: "processing"
      t.text :transcript
      t.text :summary
      t.jsonb :decisions, null: false, default: []
      t.jsonb :pending_items, null: false, default: []
      t.jsonb :tasks_suggestions, null: false, default: []
      t.text :error_message
      t.timestamps
    end
  end
end
