class AddGasStateRequiredToChecklistTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :checklist_templates, :gas_state_required, :boolean
  end
end
