class AddGasStateToChecklists < ActiveRecord::Migration[7.1]
  def change
    add_column :checklists, :gas_state, :string
  end
end
