class CreateWmsTasks < ActiveRecord::Migration[7.1]
  def change
    create_table :wms_tasks do |t|
      t.references :operator, null: false, foreign_key: true
      t.string :task_type
      t.string :plate
      t.string :task_code
      t.string :pallet
      t.datetime :started_at
      t.datetime :ended_at
      t.integer :duration, default: 0  # Em segundos

      t.timestamps
    end

    add_index :wms_tasks, :task_code
    add_index :wms_tasks, :started_at
  end
end
