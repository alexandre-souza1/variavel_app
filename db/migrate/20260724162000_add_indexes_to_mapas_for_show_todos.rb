class AddIndexesToMapasForShowTodos < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_index :mapas, [:created_at, :id], algorithm: :concurrently
    add_index :mapas, :mapa, algorithm: :concurrently
    add_index :mapas, :data, algorithm: :concurrently
    add_index :mapas, :matric_motorista, algorithm: :concurrently
    add_index :mapas, :matric_ajudante, algorithm: :concurrently
    add_index :mapas, :matric_ajudante_2, algorithm: :concurrently
  end
end
