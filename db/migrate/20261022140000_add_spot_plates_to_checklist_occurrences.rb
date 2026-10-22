class AddSpotPlatesToChecklistOccurrences < ActiveRecord::Migration[7.1]
  def up
    change_column_null :checklist_occurrences, :employee_id, true
    add_column :checklist_occurrences, :spot_plate, :string
    add_check_constraint :checklist_occurrences,
      "(employee_id IS NOT NULL AND spot_plate IS NULL) OR (employee_id IS NULL AND spot_plate IS NOT NULL)",
      name: "checklist_occurrence_exactly_one_subject"
    add_index :checklist_occurrences, [:task_id, :spot_plate, :occurred_on, :checklist_kind],
      unique: true, where: "cancelled_at IS NULL AND spot_plate IS NOT NULL", name: "index_active_spot_checklist_occurrences"
    add_index :checklist_occurrences, [:spot_plate, :occurred_on]
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Ocorrências SPOT devem ser preservadas" if select_value("SELECT 1 FROM checklist_occurrences WHERE spot_plate IS NOT NULL LIMIT 1")
    remove_check_constraint :checklist_occurrences, name: "checklist_occurrence_exactly_one_subject"
    remove_index :checklist_occurrences, name: "index_active_spot_checklist_occurrences"
    remove_index :checklist_occurrences, column: [:spot_plate, :occurred_on]
    remove_column :checklist_occurrences, :spot_plate
    change_column_null :checklist_occurrences, :employee_id, false
  end
end
