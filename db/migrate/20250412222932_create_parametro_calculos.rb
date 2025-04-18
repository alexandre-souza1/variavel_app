class CreateParametroCalculos < ActiveRecord::Migration[7.1]
  def change
    create_table :parametro_calculos do |t|
      t.string :nome
      t.decimal :valor

      t.timestamps
    end
  end
end
