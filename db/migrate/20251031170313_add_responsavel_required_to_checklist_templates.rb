class AddResponsavelRequiredToChecklistTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :checklist_templates, :responsavel_required, :boolean
  end
end
