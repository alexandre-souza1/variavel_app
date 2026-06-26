class AddObservationToChecklists < ActiveRecord::Migration[7.1]
  def change
    add_column :checklists, :observation, :text
  end
end
