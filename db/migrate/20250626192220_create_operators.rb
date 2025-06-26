class CreateOperators < ActiveRecord::Migration[7.1]
  def change
    create_table :operators do |t|
      t.integer :matricula
      t.string :nome
      t.string :cpf
      t.date :data_nascimento
      t.integer :turno

      t.timestamps
    end
  end
end
