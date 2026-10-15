class AttributeAiUsageToUsers < ActiveRecord::Migration[7.1]
  def up
    add_reference :ai_api_requests, :user, null: true, foreign_key: { on_delete: :nullify }
    add_column :ai_settings, :user_usage_tracking_started_at, :datetime, null: false, default: -> { "CURRENT_TIMESTAMP" }

    # Cotas do projeto informadas pelo administrador no AI Studio em 15/10/2026.
    # Os contadores de consumo da captura não são importados como chamadas do app.
    limits = {
      "gemini-3.6-flash" => { rpm: 5, tpm: 250_000, rpd: 20 },
      "gemini-3.1-flash-lite" => { rpm: 15, tpm: 250_000, rpd: 500 },
      "gemini-3.5-flash-lite" => { rpm: 15, tpm: 250_000, rpd: 500 },
      "gemini-2.5-flash-lite" => { rpm: 10, tpm: 250_000, rpd: 20 }
    }
    execute "UPDATE ai_settings SET model_limits = model_limits || #{connection.quote(limits.to_json)}::jsonb"
  end

  def down
    remove_column :ai_settings, :user_usage_tracking_started_at
    remove_reference :ai_api_requests, :user, foreign_key: true
  end
end
