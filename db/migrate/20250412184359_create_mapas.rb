class CreateMapas < ActiveRecord::Migration[7.1]
  def change
    create_table :mapas do |t|
      t.string :mapa
      t.date :data
      t.string :matric_motorista
      t.float :fator
      t.integer :cx_total
      t.integer :cx_real
      t.integer :pdv_total
      t.integer :pdv_real
      t.string :recarga

      t.timestamps
    end
  end
end
