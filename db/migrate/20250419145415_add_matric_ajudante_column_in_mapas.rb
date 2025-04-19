class AddMatricAjudanteColumnInMapas < ActiveRecord::Migration[7.1]
  def change
    add_column :mapas, :matric_ajudante, :string
  end
end
