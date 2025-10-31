class RenameVechileModelRequiredToVehicleModelRequiredInChecklistTemplates < ActiveRecord::Migration[7.1]
  def change
    rename_column :checklist_templates, :vechile_model_required, :vehicle_model_required
  end
end
