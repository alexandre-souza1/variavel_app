class MoveRoutineReferenceDaysToRoutines < ActiveRecord::Migration[7.1]
  def change
    add_column :routines, :weekly_reference_weekday, :integer
    add_column :routines, :monthly_reference_day, :integer

    remove_column :routine_indicators, :weekly_reference_weekday, :integer
    remove_column :routine_indicators, :monthly_reference_day, :integer
  end
end
