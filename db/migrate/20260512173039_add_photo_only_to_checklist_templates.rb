class AddPhotoOnlyToChecklistTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :checklist_templates, :photo_only, :boolean, default: false
  end
end