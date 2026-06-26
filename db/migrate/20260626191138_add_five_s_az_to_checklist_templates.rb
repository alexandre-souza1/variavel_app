class AddFiveSAzToChecklistTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :checklist_templates, :five_s_az, :boolean
  end
end
