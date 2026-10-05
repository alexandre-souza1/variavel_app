class LinkRoutinesToActionPlans < ActiveRecord::Migration[7.1]
  def change
    add_reference :routines, :action_plan, foreign_key: true

    remove_index :routines, name: "idx_unique_routine_period",
                 column: %i[routine_template_id period_start period_end], unique: true
    add_index :routines, %i[action_plan_id routine_template_id period_start period_end],
              unique: true, where: "action_plan_id IS NOT NULL", name: "idx_unique_plan_routine_period"
    add_index :routines, %i[routine_template_id period_start period_end],
              unique: true, where: "action_plan_id IS NULL", name: "idx_unique_legacy_routine_period"

    create_table :routine_category_buckets do |t|
      t.references :action_plan, null: false, foreign_key: true
      t.references :routine_category, null: false, foreign_key: true
      t.references :bucket, null: false, foreign_key: true
      t.timestamps
    end
    add_index :routine_category_buckets, %i[action_plan_id routine_category_id],
              unique: true, name: "idx_unique_plan_routine_category"

    add_reference :tasks, :routine_value, index: { unique: true },
                  foreign_key: { on_delete: :nullify }
  end
end
