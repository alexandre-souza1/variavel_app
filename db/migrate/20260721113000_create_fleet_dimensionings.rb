class CreateFleetDimensionings < ActiveRecord::Migration[7.1]
  def change
    create_table :fleet_dimensionings do |t|
      t.string :label, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.integer :route_quantity, default: 0, null: false
      t.integer :van_quantity, default: 0, null: false
      t.integer :vespertina_quantity, default: 0, null: false
      t.integer :as_quantity, default: 0, null: false

      t.timestamps
    end

    add_index :fleet_dimensionings, :label, unique: true
    add_index :fleet_dimensionings, [:start_date, :end_date]
  end
end
