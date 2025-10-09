class CreateRemunerationPeriods < ActiveRecord::Migration[7.1]
  def change
    create_table :remuneration_periods do |t|
      t.string :label, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false

      t.timestamps
    end

    add_index :remuneration_periods, :label, unique: true
  end
end
