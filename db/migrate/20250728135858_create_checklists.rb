class CreateChecklists < ActiveRecord::Migration[7.1]
  def change
    create_table :checklists do |t|
      t.references :user, null: false, foreign_key: true
      t.references :checklist_template, null: false, foreign_key: true

      t.timestamps
    end
  end
end
