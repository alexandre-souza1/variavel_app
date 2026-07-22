class AddLockingAndUniqueDateToFleetAvailabilities < ActiveRecord::Migration[7.1]
  def change
    add_column :fleet_availabilities, :locked_at, :datetime
    add_reference :fleet_availabilities,
                  :locked_by,
                  foreign_key: { to_table: :users }

    remove_index :fleet_availabilities,
                 name: "idx_fleet_availability_user_date",
                 if_exists: true
    add_index :fleet_availabilities,
              :date,
              unique: true,
              name: "idx_fleet_availability_date"
  end
end
