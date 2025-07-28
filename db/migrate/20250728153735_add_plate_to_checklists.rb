class AddPlateToChecklists < ActiveRecord::Migration[7.1]
  def change
    add_reference :checklists, :plate, foreign_key: true
  end
end
