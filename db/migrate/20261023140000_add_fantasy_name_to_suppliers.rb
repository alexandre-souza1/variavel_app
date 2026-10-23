class AddFantasyNameToSuppliers < ActiveRecord::Migration[7.1]
  def change
    add_column :suppliers, :fantasy_name, :string
  end
end
