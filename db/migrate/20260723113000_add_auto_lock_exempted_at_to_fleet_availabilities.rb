class AddAutoLockExemptedAtToFleetAvailabilities < ActiveRecord::Migration[7.1]
  def change
    add_column :fleet_availabilities, :auto_lock_exempted_at, :datetime
  end
end
