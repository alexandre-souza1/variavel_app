class AttributeAiUsageToCollaborators < ActiveRecord::Migration[7.1]
  def change
    add_reference :ai_api_requests, :collaborator, polymorphic: true, null: true
    add_check_constraint :ai_api_requests,
      "(collaborator_type IS NULL AND collaborator_id IS NULL) OR " \
      "(collaborator_type IS NOT NULL AND collaborator_type IN ('Employee', 'Driver', 'Operator', 'Ajudante', 'AzAjudante') " \
      "AND collaborator_id IS NOT NULL AND user_id IS NULL)",
      name: "ai_api_requests_valid_collaborator"
    add_column :ai_settings, :collaborator_usage_tracking_started_at, :datetime,
      null: false, default: -> { "CURRENT_TIMESTAMP" }
  end
end
