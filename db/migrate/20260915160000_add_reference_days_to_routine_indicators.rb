class AddReferenceDaysToRoutineIndicators < ActiveRecord::Migration[7.1]
  def change
    add_column :routine_indicators, :weekly_reference_weekday, :integer
    add_column :routine_indicators, :monthly_reference_day, :integer
  end
end
