class AddKilometerRequiredToChecklistTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :checklist_templates, :kilometer_required, :boolean
  end
end
