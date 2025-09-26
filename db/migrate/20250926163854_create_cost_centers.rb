class CreateCostCenters < ActiveRecord::Migration[7.1]
  def change
    create_table :cost_centers do |t|
      t.string :name
      t.string :sector

      t.timestamps
    end
  end
end
