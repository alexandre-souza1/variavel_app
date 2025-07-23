class CreatePlates < ActiveRecord::Migration[7.1]
  def change
    create_table :plates do |t|
      t.string :placa
      t.string :setor
      t.string :perfil
      t.string :tipo

      t.timestamps
    end
  end
end
