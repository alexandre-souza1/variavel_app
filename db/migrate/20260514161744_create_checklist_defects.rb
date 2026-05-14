class CreateChecklistDefects < ActiveRecord::Migration[7.1]
  def change
    create_table :checklist_defects do |t|
      t.references :checklist, null: false, foreign_key: true
      t.text :description
      t.string :location

      t.timestamps
    end
  end
end
