class EnableAiAutomationDrafts < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :ai_action_requests, name: "ai_action_requests_valid_kind"
    add_check_constraint :ai_action_requests, "kind IN ('create_task', 'create_plan', 'update_task', 'create_automation')", name: "ai_action_requests_valid_kind"
    add_column :ai_conversations, :automation_setup, :jsonb, null: false, default: {}
  end

  def down
    if select_value("SELECT 1 FROM ai_action_requests WHERE kind = 'create_automation' LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, "Há propostas de automação; preserve o histórico de confirmação."
    end
    remove_column :ai_conversations, :automation_setup
    remove_check_constraint :ai_action_requests, name: "ai_action_requests_valid_kind"
    add_check_constraint :ai_action_requests, "kind IN ('create_task', 'create_plan', 'update_task')", name: "ai_action_requests_valid_kind"
  end
end
