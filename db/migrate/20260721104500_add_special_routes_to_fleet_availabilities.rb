class AddSpecialRoutesToFleetAvailabilities < ActiveRecord::Migration[7.1]
  def change
    add_column :fleet_availabilities, :special_routes, :json, default: {}, null: false
    add_column :fleet_availability_items, :special_route, :string
  end
end
