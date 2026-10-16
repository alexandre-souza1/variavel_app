module Automations
  module Actions
    class CreateTask
      def self.validate!(rule)
        Configuration.check_keys!(rule.action_config, %w[title body bucket_id due_in_days])
        Message.validate!(rule.action_config["title"], required: true, max: 200)
        Message.validate!(rule.action_config["body"])
        if rule.action_config["bucket_id"].present? && !Configuration.buckets_for(rule.user).exists?(id: rule.action_config["bucket_id"])
          raise Invalid, "Bucket de destino indisponível para o responsável."
        end
        days = rule.action_config["due_in_days"]
        raise Invalid, "O prazo deve ser um número de dias entre 0 e 365." if days.present? && (!days.to_s.match?(/\A\d+\z/) || !days.to_i.between?(0, 365))
      end

      def self.preview(rule, period:, result:)
        bucket = Configuration.buckets_for(rule.user).includes(:action_plan).find_by(id: rule.action_config["bucket_id"])
        { label: bucket ? "#{bucket.action_plan.name} / #{bucket.name}" : "Entrada pessoal do responsável",
          title: Message.render(rule.action_config["title"], rule: rule, period: period, result: result),
          body: Message.render(rule.action_config["body"], rule: rule, period: period, result: result) }
      end

      def self.execute!(rule, period:, result:, now:)
        destination = preview(rule, period: period, result: result)
        bucket = rule.action_config["bucket_id"].present? ? Configuration.buckets_for(rule.user).find(rule.action_config["bucket_id"]) : rule.user.personal_inbox!
        days = rule.action_config["due_in_days"]
        task = bucket.tasks.create!(title: destination[:title], creator: rule.user, users: [rule.user],
          due_at: days.present? ? (now.to_date + days.to_i).in_time_zone.end_of_day : nil,
          description: [destination[:body].presence, Message.summary(rule, period: period, result: result)].compact.join("\n\n"))
        TaskActivityService.log(task: task, user: rule.user, activity_type: :created,
          metadata: { source: "automation", automation_rule_id: rule.id })
        routes = Rails.application.routes.url_helpers
        path = task.inbox? ? routes.inbox_path(task_id: task.id) : routes.action_plan_path(bucket.action_plan_id, task_id: task.id)
        { status: "success", message: "Tarefa criada para o responsável.", destination: destination.merge(path: path, task_id: task.id) }
      end
    end
  end
end
