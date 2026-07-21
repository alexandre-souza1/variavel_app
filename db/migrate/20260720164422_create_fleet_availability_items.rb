class CreateFleetAvailabilityItems < ActiveRecord::Migration[7.1]
  def change
    create_table :fleet_availability_items do |t|
      t.references :fleet_availability, null: false, foreign_key: true
      t.references :plate, null: false, foreign_key: true

      t.integer :status, default: 0
      t.integer :position, default: 0

      t.string :reason
      t.text :observation

      t.timestamps
    end
  end
end
