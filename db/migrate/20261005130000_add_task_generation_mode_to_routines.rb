class AddTaskGenerationModeToRoutines < ActiveRecord::Migration[7.1]
  def change
    add_column :routines, :task_generation_mode, :integer, default: 0, null: false
  end
end
