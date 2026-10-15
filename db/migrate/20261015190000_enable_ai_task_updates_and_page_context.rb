class EnableAiTaskUpdatesAndPageContext < ActiveRecord::Migration[7.1]
  def up
    remove_check_constraint :ai_action_requests, name: "ai_action_requests_valid_kind"
    add_check_constraint :ai_action_requests, "kind IN ('create_task', 'create_plan', 'update_task')", name: "ai_action_requests_valid_kind"
    add_column :ai_messages, :page_context, :jsonb, null: false, default: {}
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Há auditorias de alterações de tarefas; não descarte esse histórico."
  end
end
