class CreateChecklistResponses < ActiveRecord::Migration[7.1]
  def change
    create_table :checklist_responses do |t|
      t.references :checklist, null: false, foreign_key: true
      t.references :checklist_item, null: false, foreign_key: true
      t.string :status
      t.text :comment
      t.string :photo

      t.timestamps
    end
  end
end
