class AutomationRun < ApplicationRecord
  STATUSES = { "success" => "Executada", "unchanged" => "Sem alteração", "skipped" => "Não executada", "failed" => "Falhou" }.freeze
  belongs_to :automation_rule
  belongs_to :actor, class_name: "User", optional: true
  def status_label = STATUSES.fetch(status)
end
