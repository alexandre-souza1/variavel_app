class AddSectorToRoutineTemplates < ActiveRecord::Migration[7.1]
  def change
    add_column :routine_templates, :sector, :integer, null: false, default: 0
  end
end
