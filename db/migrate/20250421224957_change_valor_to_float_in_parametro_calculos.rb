class ChangeValorToFloatInParametroCalculos < ActiveRecord::Migration[7.1]
  def change
    change_column :parametro_calculos, :valor, :float
  end
end
