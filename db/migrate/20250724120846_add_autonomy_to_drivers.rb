class AddAutonomyToDrivers < ActiveRecord::Migration[7.1]
  def change
    add_column :drivers, :autonomy, :boolean, default: false, null: false
  end
end
