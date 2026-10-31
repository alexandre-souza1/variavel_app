class AddDailySummaries < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :daily_summary_enabled, :boolean, null: false, default: false
    add_column :users, :daily_summary_next_run_at, :datetime
    add_index :users, :daily_summary_next_run_at, where: "daily_summary_enabled = TRUE AND active = TRUE"

    create_table :daily_summaries do |t|
      t.references :user, null: false, foreign_key: true
      t.date :summary_date, null: false
      t.integer :status, null: false, default: 0
      t.text :content
      t.jsonb :sources, null: false, default: []
      t.integer :attempts, null: false, default: 0
      t.datetime :next_attempt_at, null: false
      t.datetime :processing_started_at
      t.string :processing_token
      t.string :last_error
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :daily_summaries, [:user_id, :summary_date], unique: true
  end
end
