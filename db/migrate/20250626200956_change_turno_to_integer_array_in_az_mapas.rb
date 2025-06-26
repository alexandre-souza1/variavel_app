class ChangeTurnoToIntegerArrayInAzMapas < ActiveRecord::Migration[7.1]
  def change
    change_column :az_mapas, :turno, :integer, array: true, default: [], using: 'ARRAY[turno]'
  end
end
