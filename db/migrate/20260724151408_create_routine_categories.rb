class CreateRoutineCategories < ActiveRecord::Migration[7.1]
  def change
    create_table :routine_categories do |t|
      t.references :routine_template, null: false, foreign_key: true

      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.boolean :collapsed, null: false, default: false

      t.timestamps
    end

    add_index :routine_categories,
              [:routine_template_id, :position]

    add_index :routine_categories,
              [:routine_template_id, :name],
              unique: true
  end
end
