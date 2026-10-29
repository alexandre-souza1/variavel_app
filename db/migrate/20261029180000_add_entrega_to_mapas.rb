class AddEntregaToMapas < ActiveRecord::Migration[7.1]
  def change
    add_column :mapas, :entrega, :string, default: 'Rota', null: false
    add_check_constraint :mapas, "entrega IN ('Rota', 'AS')", name: 'mapas_valid_entrega'
  end
end
