class ChangeGasStateTypeInChecklistsToString < ActiveRecord::Migration[7.1]
  def change
    change_column :checklists, :gas_state, :string
  end
end
