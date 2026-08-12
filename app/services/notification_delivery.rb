class NotificationDelivery
  include Rails.application.routes.url_helpers

  def self.task_assigned(task:, user:, actor:)
    new.task_assigned(task: task, user: user, actor: actor)
  end

  def self.fleet_availability_sent(fleet_availability:, actor:)
    new.fleet_availability_sent(
      fleet_availability: fleet_availability,
      actor: actor
    )
  end

  def task_assigned(task:, user:, actor:)
    Notification.create!(
      user: user,
      actor: actor,
      notifiable: task,
      kind: "task_assigned",
      title: "Nova tarefa para você",
      body: task.title,
      action_text: "Abrir tarefa",
      action_url: action_plan_path(task.bucket.action_plan)
    )
  end

  def fleet_availability_sent(fleet_availability:, actor:)
    recipients_for_fleet_availability(actor).find_each do |user|
      Notification.create!(
        user: user,
        actor: actor,
        notifiable: fleet_availability,
        kind: "fleet_availability_sent",
        title: "Disponibilidade enviada",
        body: "Disponibilidade de #{I18n.l(fleet_availability.date)} disponível para download.",
        action_text: "Baixar PDF",
        action_url: fleet_availability_path(
          fleet_availability,
          format: :pdf,
          download: true
        )
      )
    end
  end

  private

  def recipients_for_fleet_availability(actor)
    User
      .where(sector: User.sectors[:fleet])
      .or(User.where(role: User.roles[:admin]))
      .where.not(id: actor&.id)
      .distinct
  end
end
