class AddMaintenanceSuppliersToFleetAvailability < ActiveRecord::Migration[7.1]
  def change
    add_column :suppliers, :supplier_type, :string, default: "other", null: false
    add_reference :fleet_availability_items, :supplier, foreign_key: true
    add_reference :fleet_availability_changes, :supplier, foreign_key: true
  end
end
