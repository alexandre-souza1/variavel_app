class CreateRoutineTemplates < ActiveRecord::Migration[7.1]
  def change
    create_table :routine_templates do |t|
      t.string :name, null: false
      t.text :description
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :routine_templates, :name, unique: true
  end
end
