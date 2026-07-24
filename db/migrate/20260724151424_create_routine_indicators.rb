class CreateRoutineIndicators < ActiveRecord::Migration[7.1]
  def change
    create_table :routine_indicators do |t|
      t.references :routine_category, null: false, foreign_key: true

      t.string :name, null: false
      t.text :description

      t.integer :position, null: false, default: 0

      t.integer :calculation_type, null: false, default: 0
      t.integer :value_type, null: false, default: 0
      t.integer :goal_direction, null: false, default: 0

      t.boolean :required, null: false, default: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :routine_indicators,
              [:routine_category_id, :position]
  end
end
