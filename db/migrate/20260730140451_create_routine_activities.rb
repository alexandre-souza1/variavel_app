class CreateRoutineActivities < ActiveRecord::Migration[7.1]
  def change
    create_table :routine_activities do |t|
      t.references :routine,
                   null: false,
                   foreign_key: true

      t.references :user,
                   null: false,
                   foreign_key: true

      t.references :routine_value,
                   null: true,
                   foreign_key: true

      t.integer :activity_type,
                null: false,
                default: 0

      t.decimal :previous_value,
                precision: 15,
                scale: 4

      t.decimal :new_value,
                precision: 15,
                scale: 4

      t.jsonb :metadata,
              null: false,
              default: {}

      t.timestamps
    end

    add_index :routine_activities,
              %i[routine_id created_at]

    add_index :routine_activities,
              :activity_type
  end
end
