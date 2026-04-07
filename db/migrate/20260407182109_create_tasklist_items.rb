class CreateTasklistItems < ActiveRecord::Migration[7.1]
  def change
    create_table :tasklist_items do |t|
      t.string :content
      t.boolean :completed
      t.references :tasklist, null: false, foreign_key: true

      t.timestamps
    end
  end
end
