class CreateVehicleRemunerations < ActiveRecord::Migration[7.1]
  def change
    create_table :vehicle_remunerations do |t|
      t.references :remuneration_period, null: false, foreign_key: true
      t.string :vehicle_type, null: false
      t.integer :fleet_quantity, default: 0
      t.decimal :km_remunerated, precision: 12, scale: 2

      t.timestamps
    end

    add_index :vehicle_remunerations, [:remuneration_period_id, :vehicle_type], unique: true, name: "index_vr_on_period_and_vehicle"
  end
end
