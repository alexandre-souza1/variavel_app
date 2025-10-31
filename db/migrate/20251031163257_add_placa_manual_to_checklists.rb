class AddPlacaManualToChecklists < ActiveRecord::Migration[7.1]
  def change
    add_column :checklists, :placa_manual, :string
  end
end
