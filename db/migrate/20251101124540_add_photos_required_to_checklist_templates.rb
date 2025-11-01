class AddPhotosRequiredToChecklistTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :checklist_templates, :Photos_required, :boolean
  end
end
