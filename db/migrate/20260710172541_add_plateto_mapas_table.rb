class AddPlatetoMapasTable < ActiveRecord::Migration[7.1]
  def change
    add_column :mapas, :plate, :string
  end
end
