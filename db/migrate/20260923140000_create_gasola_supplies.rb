class CreateGasolaSupplies < ActiveRecord::Migration[7.1]
  def change
    create_table :gasola_supplies do |t|
      t.string :external_id, null: false
      t.string :registration
      t.string :plate
      t.string :fuel
      t.string :category
      t.string :status
      t.datetime :concluded_at, null: false
      t.decimal :liters, precision: 16, scale: 6
      t.decimal :distance, precision: 16, scale: 6
      t.decimal :goal, precision: 16, scale: 6
      t.timestamps
    end
    add_index :gasola_supplies, :external_id, unique: true
    add_index :gasola_supplies, [:registration, :concluded_at]
    create_table :gasola_sync_runs do |t|
      t.datetime :from_at, null: false
      t.datetime :to_at, null: false
      t.integer :records_count, null: false, default: 0
      t.timestamps
    end
  end
end
