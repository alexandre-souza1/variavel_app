class AddCoverageToTimeOffSchedules < ActiveRecord::Migration[7.1]
  def change
    add_column :time_off_memberships, :standard_operation, :string
    add_check_constraint :time_off_memberships,
      "standard_operation IS NULL OR (group_code = 'FIXO' AND fixed_weekday = 6 AND (standard_operation = 'vespertina' OR (standard_operation = 'as' AND driver_id IS NOT NULL)))",
      name: 'time_off_valid_standard_operation'
    create_table :time_off_daily_plans do |t|
      t.references :time_off_schedule, null: false, foreign_key: true
      t.date :date, null: false
      t.jsonb :details, null: false, default: {}
      t.string :dimensioning_signature, null: false
      t.string :reason, null: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :time_off_daily_plans, [:time_off_schedule_id, :date], unique: true, name: 'time_off_one_plan_per_day'
    change_column_null :time_off_changes, :time_off_membership_id, true
  end
end
