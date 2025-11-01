class AddOriginToChecklists < ActiveRecord::Migration[7.1]
  def change
    add_column :checklists, :origin, :string
  end
end
