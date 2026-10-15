class CreateAiActionRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_action_requests do |t|
      t.references :user, null: false, foreign_key: true
      t.references :ai_conversation, null: false, foreign_key: true
      t.references :ai_message, foreign_key: { on_delete: :nullify }
      t.string :kind, null: false
      t.string :status, null: false, default: "pending"
      t.string :confirmation_token, null: false
      t.jsonb :payload, null: false, default: {}
      t.jsonb :preview, null: false, default: {}
      t.jsonb :result, null: false, default: {}
      t.datetime :expires_at, null: false
      t.datetime :executed_at
      t.datetime :cancelled_at
      t.timestamps
    end
    add_check_constraint :ai_action_requests, "kind IN ('create_task', 'create_plan')", name: "ai_action_requests_valid_kind"
    add_check_constraint :ai_action_requests, "status IN ('pending', 'executed', 'cancelled')", name: "ai_action_requests_valid_status"
    add_index :ai_action_requests, [:ai_conversation_id, :status]
  end
end
