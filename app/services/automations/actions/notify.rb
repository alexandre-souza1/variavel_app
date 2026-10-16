module Automations
  module Actions
    class Notify
      def self.validate!(rule)
        Configuration.check_keys!(rule.action_config, %w[title body])
        Message.validate!(rule.action_config["title"], required: true, max: 200)
        Message.validate!(rule.action_config["body"])
      end

      def self.preview(rule, period:, result:)
        { label: "Avisos do responsável: #{rule.user.name.presence || rule.user.email}",
          title: Message.render(rule.action_config["title"], rule: rule, period: period, result: result),
          body: Message.render(rule.action_config["body"], rule: rule, period: period, result: result) }
      end

      def self.execute!(rule, period:, result:, now:)
        destination = preview(rule, period: period, result: result)
        path = Rails.application.routes.url_helpers.automation_rule_path(rule)
        notification = Notification.create!(user: rule.user, actor: rule.user, notifiable: rule, kind: "automation",
          title: destination[:title], body: [destination[:body].presence, Message.summary(rule, period: period, result: result)].compact.join("\n\n"),
          action_text: "Ver automação", action_url: path)
        { status: "success", message: "Aviso enviado ao responsável.", destination: destination.merge(path: path, notification_id: notification.id) }
      end
    end
  end
end
