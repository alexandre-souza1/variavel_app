class AddOriginRequiredToChecklistTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :checklist_templates, :origin_required, :boolean
  end
end
