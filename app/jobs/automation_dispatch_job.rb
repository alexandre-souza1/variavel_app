class AutomationDispatchJob < ApplicationJob
  queue_as :default

  def perform
    AutomationRule.due.order(:next_run_at).limit(100).pluck(:id).each do |id|
      rule = AutomationRule.find_by(id: id)
      Automations::Runner.call(rule, trigger: "scheduled") if rule
    end
  end
end
