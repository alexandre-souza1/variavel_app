class CreateRoutines < ActiveRecord::Migration[7.1]
  def change
    create_table :routines do |t|
      t.references :routine_template,
                   null: false,
                   foreign_key: true

      t.references :created_by,
                   null: false,
                   foreign_key: { to_table: :users }

      t.string :title

      t.date :period_start, null: false
      t.date :period_end, null: false

      t.integer :status,
                null: false,
                default: 0

      t.timestamps
    end

    add_index :routines,
              [:routine_template_id, :period_start, :period_end],
              unique: true,
              name: "idx_unique_routine_period"
  end
end
