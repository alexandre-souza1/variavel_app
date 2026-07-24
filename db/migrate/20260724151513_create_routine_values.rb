class CreateRoutineValues < ActiveRecord::Migration[7.1]
  def change
    create_table :routine_values do |t|
      t.references :routine,
                   null: false,
                   foreign_key: true

      t.references :routine_indicator,
                   null: false,
                   foreign_key: true

      t.date :reference_date,
             null: false

      t.decimal :value,
                precision: 15,
                scale: 4

      t.references :updated_by,
                   foreign_key: { to_table: :users }

      t.timestamps
    end

    add_index :routine_values,
              [:routine_id,
               :routine_indicator_id,
               :reference_date],
              unique: true,
              name: "idx_unique_routine_value"
  end
end
