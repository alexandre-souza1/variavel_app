class AddUniqueAvailablePositionToFleetAvailabilityItems < ActiveRecord::Migration[7.1]
  def change
    add_index :fleet_availability_items,
              %i[fleet_availability_id position],
              unique: true,
              where: "status = 0",
              name: "index_fleet_availability_items_on_unique_available_position"
  end
end
