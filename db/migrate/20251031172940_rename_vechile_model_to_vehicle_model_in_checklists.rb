class RenameVechileModelToVehicleModelInChecklists < ActiveRecord::Migration[7.1]
  def change
    rename_column :checklists, :vechile_model, :vehicle_model
  end
end
