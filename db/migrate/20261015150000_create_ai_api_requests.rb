class CreateAiApiRequests < ActiveRecord::Migration[7.1]
  def change
    create_table :ai_api_requests do |t|
      t.string :model, null: false
      t.string :feature, null: false
      t.string :credential_fingerprint, null: false
      t.datetime :requested_at, null: false
      t.integer :http_status
      t.integer :duration_ms, null: false
      t.bigint :input_tokens
      t.bigint :output_tokens
      t.bigint :total_tokens
      t.datetime :retry_at
    end
    add_index :ai_api_requests, [:credential_fingerprint, :requested_at], name: "index_ai_api_requests_on_credential_and_time"
    add_index :ai_api_requests, [:model, :requested_at]
  end
end
