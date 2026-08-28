class AddAutoOpenTimeToFleetAvailabilitySettings < ActiveRecord::Migration[7.1]
  def change
    add_column :fleet_availability_settings, :auto_open_time, :string,
               null: false, default: "08:00"
  end
end
