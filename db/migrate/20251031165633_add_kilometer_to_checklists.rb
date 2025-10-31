class AddKilometerToChecklists < ActiveRecord::Migration[7.1]
  def change
    add_column :checklists, :kilometer, :float
  end
end
