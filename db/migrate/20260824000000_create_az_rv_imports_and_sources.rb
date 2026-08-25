class CreateAzRvImportsAndSources < ActiveRecord::Migration[7.1]
  def change
    create_table :az_rv_imports do |t|
      t.string :source_type, null: false
      t.date :reference_date
      t.string :original_filename, null: false
      t.string :file_digest, null: false
      t.string :status, null: false, default: "completed"
      t.integer :rows_imported, null: false, default: 0
      t.integer :rows_skipped, null: false, default: 0
      t.text :error_message
      t.references :user, foreign_key: true
      t.timestamps
    end

    add_index :az_rv_imports, [:source_type, :file_digest], unique: true

    create_table :az_rv_points do |t|
      t.references :az_rv_import, null: false, foreign_key: true
      t.string :employee_name, null: false
      t.string :employee_key, null: false
      t.date :reference_date, null: false
      t.decimal :credits, precision: 16, scale: 2, null: false, default: 0
      t.decimal :debits, precision: 16, scale: 2, null: false, default: 0
      t.decimal :total_points, precision: 16, scale: 2, null: false, default: 0
      t.decimal :reported_value, precision: 16, scale: 2, null: false, default: 0
      t.timestamps
    end

    add_index :az_rv_points, [:employee_key, :reference_date], unique: true

    create_table :az_rv_tasks do |t|
      t.references :az_rv_import, null: false, foreign_key: true
      t.string :source_key, null: false
      t.string :warehouse
      t.string :map_code
      t.string :task_number
      t.string :horse_plate
      t.string :trailer_plate
      t.string :origin
      t.string :destination
      t.string :pallet
      t.string :priority
      t.string :status
      t.string :task_type
      t.string :employee_name, null: false
      t.string :employee_key, null: false
      t.datetime :created_at_source
      t.datetime :associated_at
      t.datetime :changed_at
      t.datetime :released_at
      t.string :completed_task
      t.timestamps
    end

    add_index :az_rv_tasks, :source_key, unique: true
    add_index :az_rv_tasks, [:employee_key, :created_at_source]

    create_table :az_rv_on_demand_activities do |t|
      t.references :az_rv_import, null: false, foreign_key: true
      t.string :source_key, null: false
      t.string :warehouse
      t.string :activity
      t.string :activity_code
      t.string :address
      t.string :task_number
      t.string :employee_name, null: false
      t.string :employee_key, null: false
      t.datetime :created_at_source
      t.datetime :associated_at
      t.datetime :finalized_at
      t.string :validation_status
      t.string :task_status
      t.text :observation
      t.string :plate
      t.string :vehicle_type
      t.string :transport_type
      t.timestamps
    end

    add_index :az_rv_on_demand_activities, :source_key, unique: true
    add_index :az_rv_on_demand_activities, [:employee_key, :created_at_source], name: "index_az_rv_ondemand_on_employee_and_date"
  end
end
