class CreateAutonomies < ActiveRecord::Migration[7.1]
  def change
    create_table :autonomies do |t|
      t.string :registration
      t.string :equipment_type
      t.string :service_type
      t.string :plate
      t.text :report
      t.string :evidence
      t.string :user_type
      t.integer :user_id

      t.timestamps
    end
  end
end
