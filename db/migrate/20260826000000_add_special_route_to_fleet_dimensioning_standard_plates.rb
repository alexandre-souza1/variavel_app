class AddSpecialRouteToFleetDimensioningStandardPlates < ActiveRecord::Migration[7.1]
  def change
    add_column :fleet_dimensioning_standard_plates, :special_route, :string
    change_column_null :fleet_dimensioning_standard_plates, :position, true

    remove_index :fleet_dimensioning_standard_plates,
                 name: "idx_fleet_dimensioning_standard_plate_position"
    add_index :fleet_dimensioning_standard_plates,
              [:fleet_dimensioning_id, :position],
              unique: true,
              where: "special_route IS NULL",
              name: "idx_dimensioning_standard_plate_position"
    add_index :fleet_dimensioning_standard_plates,
              [:fleet_dimensioning_id, :special_route],
              unique: true,
              where: "special_route IS NOT NULL",
              name: "idx_dimensioning_standard_plate_route"
  end
end
