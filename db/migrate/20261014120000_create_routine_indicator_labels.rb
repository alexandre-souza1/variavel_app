class CreateRoutineIndicatorLabels < ActiveRecord::Migration[7.1]
  def change
    create_table :routine_indicator_labels do |t|
      t.references :routine_indicator, null: false, foreign_key: true
      t.references :label, null: false, foreign_key: true
      t.timestamps
    end

    add_index :routine_indicator_labels, %i[routine_indicator_id label_id],
              unique: true, name: "idx_unique_routine_indicator_label"
  end
end
