class CreateAutomationModule < ActiveRecord::Migration[7.1]
  def change
    create_table :automation_rules do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :source_key, null: false
      t.string :operation, null: false, default: "count"
      t.string :period, null: false, default: "today"
      t.jsonb :filters, null: false, default: {}
      t.string :condition_operator, null: false, default: "always"
      t.decimal :condition_value, precision: 18, scale: 4
      t.string :action_key, null: false
      t.jsonb :action_config, null: false, default: {}
      t.string :schedule, null: false, default: "manual"
      t.integer :execution_hour, null: false, default: 8
      t.integer :weekday, null: false, default: 1
      t.integer :month_day, null: false, default: 1
      t.boolean :enabled, null: false, default: false
      t.datetime :next_run_at
      t.timestamps
    end
    add_index :automation_rules, :next_run_at, where: "enabled = true"
    add_index :automation_rules,
      "(action_config->>'routine_template_id'), (action_config->>'routine_indicator_id')",
      unique: true, where: "enabled = true AND action_key = 'update_indicator'",
      name: "idx_enabled_automation_indicator"
    add_reference :routine_values, :automation_rule, foreign_key: { on_delete: :nullify }

    create_table :automation_runs do |t|
      t.references :automation_rule, null: false, foreign_key: true
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :trigger, null: false
      t.string :status, null: false
      t.string :message, null: false
      t.string :effect_key
      t.jsonb :details, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :automation_runs, [:automation_rule_id, :created_at]
    add_index :automation_runs, [:automation_rule_id, :effect_key], unique: true,
      where: "effect_key IS NOT NULL", name: "idx_unique_automation_effect"
    add_check_constraint :automation_runs, "status IN ('success', 'unchanged', 'skipped', 'failed')", name: "automation_runs_valid_status"
  end
end
