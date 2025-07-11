class CreateAzAjudantes < ActiveRecord::Migration[7.1]
  def change
    create_table :az_ajudantes do |t|
      t.integer :matricula
      t.string :nome
      t.string :cpf
      t.date :data_nascimento
      t.integer :turno

      t.timestamps
    end
  end
end
