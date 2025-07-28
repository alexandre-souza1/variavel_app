class AddPlateRequiredToChecklistTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :checklist_templates, :plate_required, :boolean
  end
end
