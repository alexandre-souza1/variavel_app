namespace :task_notifications do
  desc "Envia avisos de vencimento nas janelas de 48 e 24 horas, uma vez por janela"
  task due_soon: :environment do
    TaskDueNotificationService.call
  end
end
