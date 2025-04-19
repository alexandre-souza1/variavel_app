class CreateAjudantes < ActiveRecord::Migration[7.1]
  def change
    create_table :ajudantes do |t|
      t.string :matricula
      t.string :promax
      t.string :nome
      t.string :cpf
      t.date :data_nascimento

      t.timestamps
    end
  end
end
