class AddActiveToPlates < ActiveRecord::Migration[7.1]
  def change
    add_column :plates, :active, :boolean, null: false, default: true
    add_column :plates, :retired_at, :date
    add_index :plates, :active
  end
end
