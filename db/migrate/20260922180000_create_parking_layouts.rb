class CreateParkingLayouts < ActiveRecord::Migration[7.1]
  def change
    create_table :parking_layouts do |t|
      t.jsonb :assignments, null: false, default: {}
      t.integer :lock_version, null: false, default: 0
      t.references :updated_by, foreign_key: { to_table: :users }, null: true
      t.timestamps
    end
    add_check_constraint :parking_layouts, "id = 1", name: "parking_layouts_singleton"
  end
end
