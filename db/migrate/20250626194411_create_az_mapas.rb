class CreateAzMapas < ActiveRecord::Migration[7.1]
  def change
    create_table :az_mapas do |t|
      t.date :data
      t.integer :turno
      t.integer :tipo
      t.float :resultado
      t.boolean :atingiu_meta, default: false

      t.timestamps
    end
  end
end
