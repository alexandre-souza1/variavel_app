class CreateFleetAvailabilityChanges < ActiveRecord::Migration[7.1]
  def change
    create_table :fleet_availability_changes do |t|
      t.references :fleet_availability_item, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :from_status
      t.integer :to_status
      t.string :reason
      t.text :observation

      t.timestamps
    end
  end
end
