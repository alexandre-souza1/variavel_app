class ChangeCamposToFloatInMapas < ActiveRecord::Migration[7.1]
  def change
    change_column :mapas, :cx_total, :float
    change_column :mapas, :cx_real, :float
    change_column :mapas, :pdv_total, :float
    change_column :mapas, :pdv_real, :float
  end
end
