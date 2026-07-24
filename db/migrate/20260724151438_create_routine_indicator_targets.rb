class CreateRoutineIndicatorTargets < ActiveRecord::Migration[7.1]
  def change
    create_table :routine_indicator_targets do |t|
      t.references :routine_indicator,
                   null: false,
                   foreign_key: true

      t.decimal :goal,
                precision: 15,
                scale: 4,
                null: false

      t.date :starts_at, null: false
      t.date :ends_at

      t.timestamps
    end

    add_index :routine_indicator_targets,
              [:routine_indicator_id, :starts_at],
              name: "idx_indicator_targets_start"
  end
end
