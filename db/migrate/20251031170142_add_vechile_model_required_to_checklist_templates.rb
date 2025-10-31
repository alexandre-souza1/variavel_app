class AddVechileModelRequiredToChecklistTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :checklist_templates, :vechile_model_required, :boolean
  end
end
