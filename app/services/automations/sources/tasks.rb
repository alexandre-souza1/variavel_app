module Automations
  module Sources
    class Tasks
      STATUSES = { "pending" => "Pendentes", "overdue" => "Vencidas", "completed" => "Concluídas" }.freeze

      def self.validate!(rule)
        Configuration.check_keys!(rule.filters, %w[status action_plan_id only_mine])
        raise Invalid, "Escolha a situação das tarefas." unless STATUSES.key?(rule.filters["status"])
        if rule.filters["action_plan_id"].present? && !ActionPlan.visible_to(rule.user).exists?(id: rule.filters["action_plan_id"])
          raise Invalid, "Plano de origem indisponível."
        end
      end

      def self.call(rule, period:, now:)
        scope = Task.accessible_to(rule.user)
        scope = scope.where(id: TaskAssignment.where(user_id: rule.user_id).select(:task_id))
          .or(scope.where(creator_id: rule.user_id, buckets: { inbox: true })) if rule.filters["only_mine"] == "1"
        scope = scope.where(buckets: { action_plan_id: rule.filters["action_plan_id"] }) if rule.filters["action_plan_id"].present?
        scope = if rule.filters["status"] == "completed"
          scope.where(completed: true, completed_at: period.time_range)
        else
          pending = scope.where(completed: [false, nil])
          pending = pending.where(due_at: period.time_range) if period.start_date
          rule.filters["status"] == "overdue" ? pending.where("due_at < ?", now) : pending
        end
        count = scope.distinct.count
        { value: count.to_d, count: count, available: true,
          note: "Pendentes e vencidas usam o prazo; concluídas usam a data de conclusão. Todo o histórico inclui pendências sem prazo." }
      end
    end
  end
end
