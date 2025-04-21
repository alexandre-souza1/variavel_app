class AddCategoriaToParametroCalculos < ActiveRecord::Migration[7.1]
  def change
    add_column :parametro_calculos, :categoria, :string
  end
end
