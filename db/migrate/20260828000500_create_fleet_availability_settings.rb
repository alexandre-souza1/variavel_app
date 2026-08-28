class CreateFleetAvailabilitySettings < ActiveRecord::Migration[7.1]
  def change
    create_table :fleet_availability_settings do |t|
      t.string :auto_lock_time, null: false, default: "08:00"
      t.timestamps
    end
  end
end
