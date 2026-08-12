namespace :task_notifications do
  desc "Envia notificações para tarefas com vencimento nas próximas 24 horas"
  task due_soon: :environment do
    TaskDueNotificationService.call
  end
end
