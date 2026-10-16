module Automations
  class Runner
    def self.call(rule, actor: nil, trigger: "manual", now: Time.current)
      if trigger == "manual" && !(actor&.active? && !actor.mechanical? && (actor.admin? || actor.id == rule.user_id))
        raise Invalid, "Você não tem acesso a esta automação."
      end
      rule.with_lock do
        next unless trigger == "manual" || (rule.enabled? && rule.next_run_at && rule.next_run_at <= now)
        begin
          run = AutomationRule.transaction(requires_new: true) do
            preview = Preview.call(rule, now: now)
            period, result = preview.values_at(:period, :result)
            details = { source: rule.source_key, operation: rule.operation, action: rule.action_key,
              period_start: period.start_date, period_end: period.end_date, count: result[:count], value: result[:value].to_s("F"),
              condition_met: preview[:condition_met], configuration: rule.attributes.slice("filters", "action_config", "condition_operator", "condition_value") }
            effect_key = "#{rule.action_key}:#{period.effect_key}" unless rule.action_key == "update_indicator"
            previous = rule.automation_runs.find_by(effect_key: effect_key) if effect_key
            outcome = if !result[:available]
              { status: "skipped", message: "Sem dados para o período; a ação foi preservada." }
            elsif !preview[:condition_met]
              { status: "skipped", message: "A condição da regra não foi atendida." }
            elsif previous
              { status: "unchanged", message: "A ação já foi realizada neste período.", destination: previous.details["destination"] }
            else
              Catalog::ACTIONS.fetch(rule.action_key)[:adapter].execute!(rule, period: period, result: result, now: now)
            end
            rule.automation_runs.create!(actor: actor, trigger: trigger,
              status: outcome[:status], message: outcome[:message],
              effect_key: outcome[:status] == "success" ? effect_key : nil,
              details: details.merge(destination: outcome[:destination] || preview[:destination]))
          end
        rescue Invalid => error
          run = rule.automation_runs.create!(actor: actor, trigger: trigger, status: "skipped", message: error.message.truncate(1000))
        rescue StandardError => error
          Rails.logger.error("[Automations] rule_id=#{rule.id} error_class=#{error.class.name}")
          run = rule.automation_runs.create!(actor: actor, trigger: trigger, status: "failed",
            message: "Falha ao executar. Revise a configuração e tente novamente; nenhuma ação desta tentativa foi mantida.")
        end
        rule.update_columns(next_run_at: rule.next_occurrence(after: now), updated_at: Time.current) if trigger == "scheduled"
        run
      end
    end
  end
end
