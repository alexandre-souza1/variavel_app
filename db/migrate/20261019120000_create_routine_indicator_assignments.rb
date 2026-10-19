class CreateRoutineIndicatorAssignments < ActiveRecord::Migration[7.1]
  def change
    create_table :routine_indicator_assignments do |t|
      t.references :routine_indicator, null: false, foreign_key: true, index: false
      t.references :user, null: false, foreign_key: true
      t.timestamps
    end

    add_index :routine_indicator_assignments, [:routine_indicator_id, :user_id], unique: true
  end
end
