class CreateChecklistTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :checklist_templates do |t|
      t.string :name

      t.timestamps
    end
  end
end
