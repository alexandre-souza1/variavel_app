class AddUsageLimitsToAiSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :ai_settings, :model_limits, :jsonb, null: false, default: {}
    add_column :ai_settings, :usage_tracking_started_at, :datetime, null: false, default: -> { "CURRENT_TIMESTAMP" }
  end
end
