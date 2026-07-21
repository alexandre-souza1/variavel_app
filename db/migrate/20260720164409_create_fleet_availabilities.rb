class CreateFleetAvailabilities < ActiveRecord::Migration[7.1]
  def change
    create_table :fleet_availabilities do |t|
      t.date :date, null: false
      t.integer :planned_quantity, default: 0

      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
