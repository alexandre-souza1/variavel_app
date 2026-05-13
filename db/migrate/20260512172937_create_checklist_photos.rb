class CreateChecklistPhotos < ActiveRecord::Migration[7.1]
  def change
    create_table :checklist_photos do |t|
      t.references :checklist, null: false, foreign_key: true
      t.string :kind
      t.text :description

      t.timestamps
    end
  end
end
