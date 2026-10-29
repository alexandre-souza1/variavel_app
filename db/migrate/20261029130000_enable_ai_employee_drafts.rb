class EnableAiEmployeeDrafts < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :ai_action_requests, name: "ai_action_requests_valid_kind"
    add_check_constraint :ai_action_requests, "kind IN ('create_task', 'create_plan', 'update_task', 'create_automation', 'create_employee')", name: "ai_action_requests_valid_kind"
  end

  def down
    if select_value("SELECT 1 FROM ai_action_requests WHERE kind = 'create_employee' LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, "Há propostas de cadastro de colaboradores; preserve o histórico de confirmação."
    end
    remove_check_constraint :ai_action_requests, name: "ai_action_requests_valid_kind"
    add_check_constraint :ai_action_requests, "kind IN ('create_task', 'create_plan', 'update_task', 'create_automation')", name: "ai_action_requests_valid_kind"
  end
end
