class CreateTimeOffSchedules < ActiveRecord::Migration[7.1]
  def change
    create_table :time_off_schedules do |t|
      t.string :name, null: false
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.date :rotation_anchor, null: false
      t.boolean :recurring, null: false, default: false
      t.timestamps
    end
    create_table :time_off_memberships do |t|
      t.references :time_off_schedule, null: false, foreign_key: true
      t.references :driver, foreign_key: true
      t.references :ajudante, foreign_key: true
      t.string :group_code, null: false
      t.date :starts_on, null: false
      t.date :ends_on
      t.timestamps
    end
    add_check_constraint :time_off_memberships, '(driver_id IS NOT NULL) <> (ajudante_id IS NOT NULL)', name: 'time_off_exactly_one_person'
    add_check_constraint :time_off_memberships, "group_code IN ('A','B','C','D','E','F')", name: 'time_off_valid_group'
    add_check_constraint :time_off_memberships, 'ends_on IS NULL OR ends_on >= starts_on', name: 'time_off_valid_membership_dates'
    add_index :time_off_memberships, [:time_off_schedule_id, :driver_id], unique: true, where: 'ends_on IS NULL AND driver_id IS NOT NULL', name: 'time_off_current_driver'
    add_index :time_off_memberships, [:time_off_schedule_id, :ajudante_id], unique: true, where: 'ends_on IS NULL AND ajudante_id IS NOT NULL', name: 'time_off_current_helper'
    create_table :time_off_overrides do |t|
      t.references :time_off_membership, null: false, foreign_key: true
      t.date :date, null: false
      t.string :status, null: false
      t.string :reason, null: false
      t.integer :lock_version, null: false, default: 0
      t.timestamps
    end
    add_index :time_off_overrides, [:time_off_membership_id, :date], unique: true, name: 'time_off_one_override_per_day'
    add_check_constraint :time_off_overrides, "status IN ('working','off','unavailable')", name: 'time_off_valid_status'
    create_table :time_off_changes do |t|
      t.references :time_off_schedule, null: false, foreign_key: true
      t.references :time_off_membership, null: false, foreign_key: true
      t.references :user, foreign_key: { on_delete: :nullify }
      t.date :date, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end
    reversible do |dir|
      dir.up do
        execute <<~SQL
          INSERT INTO time_off_schedules (name, starts_on, ends_on, rotation_anchor, recurring, created_at, updated_at)
          VALUES ('Piloto 5x2 • Motoristas e ajudantes', '2026-10-01', '2026-10-31', '2026-09-28', FALSE, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
        SQL
      end
    end
  end
end
