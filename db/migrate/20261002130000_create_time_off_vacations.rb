class CreateTimeOffVacations < ActiveRecord::Migration[7.1]
  def change
    create_table :time_off_vacations do |t|
      t.references :time_off_schedule, null: false, foreign_key: true
      t.references :time_off_membership, null: false, foreign_key: true
      t.date :starts_on, null: false
      t.date :ends_on, null: false
      t.text :reason, null: false
      t.datetime :cancelled_at
      t.timestamps
    end
  end
end
