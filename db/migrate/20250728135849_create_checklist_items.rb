class CreateChecklistItems < ActiveRecord::Migration[7.1]
  def change
    create_table :checklist_items do |t|
      t.references :checklist_template, null: false, foreign_key: true
      t.string :description
      t.integer :position

      t.timestamps
    end
  end
end
