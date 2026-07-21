class CreateFleetDimensioningStandardPlates < ActiveRecord::Migration[7.1]
  def change
    create_table :fleet_dimensioning_standard_plates do |t|
      t.references :fleet_dimensioning, null: false, foreign_key: true
      t.references :plate, null: false, foreign_key: true
      t.integer :position, null: false

      t.timestamps
    end

    add_index :fleet_dimensioning_standard_plates,
              [:fleet_dimensioning_id, :position],
              unique: true,
              name: "idx_fleet_dimensioning_standard_plate_position"
    add_index :fleet_dimensioning_standard_plates,
              [:fleet_dimensioning_id, :plate_id],
              unique: true,
              name: "idx_fleet_dimensioning_standard_plate_plate"
  end
end
