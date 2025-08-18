class CreateFuelConsumptions < ActiveRecord::Migration[7.1]
  def change
    create_table :fuel_consumptions do |t|
      t.string :driver_name
      t.decimal :km_per_liter
      t.decimal :km_per_liter_goal
      t.decimal :impact
      t.decimal :total_value
      t.integer :refuelings_count
      t.decimal :liters
      t.decimal :km_driven
      t.decimal :co2_impact
      t.string :period

      t.timestamps
    end
  end
end
