class AddFixedGroupToTimeOffMemberships < ActiveRecord::Migration[7.1]
  def change
    add_column :time_off_memberships, :fixed_weekday, :integer
    add_column :time_off_memberships, :pilot_key, :string
    add_index :time_off_memberships, [:time_off_schedule_id, :pilot_key], unique: true, where: 'pilot_key IS NOT NULL', name: 'time_off_pilot_slot'
    remove_check_constraint :time_off_memberships, "group_code IN ('A','B','C','D','E','F')", name: 'time_off_valid_group'
    add_check_constraint :time_off_memberships, "group_code IN ('A','B','C','D','E','F','FIXO')", name: 'time_off_valid_group'
    add_check_constraint :time_off_memberships, 'fixed_weekday IS NULL OR fixed_weekday BETWEEN 1 AND 6', name: 'time_off_valid_fixed_weekday'
    reversible do |dir|
      dir.up { execute 'UPDATE time_off_schedules SET recurring = TRUE, updated_at = CURRENT_TIMESTAMP' }
    end
  end
end
