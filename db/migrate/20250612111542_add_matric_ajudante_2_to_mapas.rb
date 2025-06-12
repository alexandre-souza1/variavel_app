class AddMatricAjudante2ToMapas < ActiveRecord::Migration[7.1]
  def change
    add_column :mapas, :matric_ajudante_2, :string
  end
end
