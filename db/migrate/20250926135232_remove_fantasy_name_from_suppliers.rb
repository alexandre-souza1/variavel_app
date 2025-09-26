class RemoveFantasyNameFromSuppliers < ActiveRecord::Migration[7.1]
  def change
    remove_column :suppliers, :fantasy_name, :string
  end
end
