class CreateRemunerationCategoryValues < ActiveRecord::Migration[7.1]
  def change
    create_table :remuneration_category_values do |t|
      t.references :vehicle_remuneration, null: false, foreign_key: true
      t.references :budget_category, null: false, foreign_key: true
      t.decimal :value, precision: 15, scale: 2, null: false

      t.timestamps
    end

    add_index :remuneration_category_values, [:vehicle_remuneration_id, :budget_category_id], unique: true, name: "index_rcv_on_vehicle_and_budget"
  end
end
