class RenamePhotosRequiredToPhotosRequiredInChecklistTemplates < ActiveRecord::Migration[7.1]
  def change
    rename_column :checklist_templates, :Photos_required, :photos_required
  end
end
