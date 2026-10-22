class AddExclusionCategoryToChecklistOccurrences < ActiveRecord::Migration[7.1]
  def change
    add_column :checklist_occurrences, :exclusion_category, :string
    add_index :checklist_occurrences, [:employee_id, :occurred_on, :checklist_kind],
      where: "exclusion_category IS NOT NULL", name: "index_justified_checklist_occurrences"
  end
end
