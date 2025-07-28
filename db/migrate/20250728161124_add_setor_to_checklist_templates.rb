class AddSetorToChecklistTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :checklist_templates, :setor, :string
  end
end
