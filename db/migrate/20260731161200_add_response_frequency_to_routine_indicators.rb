class AddResponseFrequencyToRoutineIndicators < ActiveRecord::Migration[7.1]
  def change
    add_column :routine_indicators,
               :response_frequency,
               :integer,
               null: false,
               default: 0
  end
end
