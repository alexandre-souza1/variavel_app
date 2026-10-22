class CreateChecklistOccurrences < ActiveRecord::Migration[7.1]
  def change
    create_table :checklist_occurrences do |t|
      t.references :task, null: false, foreign_key: true
      t.references :employee, null: false, foreign_key: true
      t.references :recorded_by, null: false, foreign_key: { to_table: :users }
      t.date :occurred_on, null: false
      t.string :checklist_kind, null: false
      t.text :notes
      t.datetime :cancelled_at
      t.references :cancelled_by, foreign_key: { to_table: :users }
      t.text :cancellation_reason
      t.timestamps
    end
    add_index :checklist_occurrences, [:task_id, :employee_id, :occurred_on, :checklist_kind],
      unique: true, where: "cancelled_at IS NULL", name: "index_active_checklist_occurrences"
    add_index :checklist_occurrences, [:occurred_on, :employee_id]
  end
end
