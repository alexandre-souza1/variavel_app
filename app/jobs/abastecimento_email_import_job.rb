class AbastecimentoEmailImportJob < ApplicationJob
  queue_as :default

  def perform(progress_notification_id = nil, date = Time.zone.yesterday.to_date)
    progress = lambda do |message|
      Notification.where(id: progress_notification_id, kind: "abastecimento_email_import_progress")
                  .update_all(body: message, updated_at: Time.current) if progress_notification_id
    end
    result = AbastecimentoEmailImporter.call(date: date.to_date, progress: progress)
    if progress_notification_id
      title = result.errors.empty? ? "Importação de abastecimento finalizada" : "Erro na importação de abastecimento"
      body = if result.errors.empty?
               "Importados: #{result.processed}. Ignorados: #{result.skipped}."
             else
               "Erros: #{result.errors.join(' | ')}"
             end
      Notification.where(id: progress_notification_id).update_all(kind: "abastecimento_email_import_finished", title: title, body: body, updated_at: Time.current)
    end
    Rails.logger.info(
      "[AbastecimentoEmailImportJob] date=#{result.date} " \
      "processed=#{result.processed} skipped=#{result.skipped} errors=#{result.errors.size}"
    )
  rescue StandardError => error
    Notification.where(id: progress_notification_id).update_all(
      kind: "abastecimento_email_import_finished",
      title: "Erro na importação de abastecimento",
      body: error.message,
      updated_at: Time.current
    ) if progress_notification_id
    raise
  end
end
