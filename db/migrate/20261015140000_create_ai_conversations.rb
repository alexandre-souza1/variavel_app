class CreateAiConversations < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_conversations do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string :request_token
      t.datetime :requested_at
      t.text :error_message
      t.datetime :usage_window_at
      t.integer :usage_count, null: false, default: 0
      t.timestamps
    end

    create_table :ai_messages do |t|
      t.references :ai_conversation, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content, null: false
      t.jsonb :sources, null: false, default: []
      t.timestamps
    end
    add_index :ai_messages, [:ai_conversation_id, :id]
    add_check_constraint :ai_messages, "role IN ('user', 'assistant')", name: "ai_messages_valid_role"
  end
end
