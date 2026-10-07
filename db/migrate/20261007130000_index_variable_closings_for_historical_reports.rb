class IndexVariableClosingsForHistoricalReports < ActiveRecord::Migration[7.1]
  def change
    add_index :variable_closings, [:sector, :year, :month, :employee_id, :revision], name: 'index_variable_closings_history'
  end
end
