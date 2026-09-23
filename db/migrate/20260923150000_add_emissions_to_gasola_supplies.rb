class AddEmissionsToGasolaSupplies < ActiveRecord::Migration[7.1]
  def change
    add_column :gasola_supplies, :co2_emission, :decimal, precision: 20, scale: 6
    add_column :gasola_supplies, :co2_goal, :decimal, precision: 20, scale: 6
    add_column :gasola_supplies, :co2_impact, :decimal, precision: 20, scale: 6
  end
end
