class WmsTaskImportJob < ApplicationJob
  queue_as :default

  def perform(file_path, user_id = nil, original_filename = nil)
    file_path = file_path.to_s

    unless File.exist?(file_path)
      show_result(user_id, "❌ Arquivo não encontrado", false, true)
      return
    end

    result = SharedTasksImportService.new(
      file: file_path,
      user: User.find_by(id: user_id),
      original_filename: original_filename,
      progress: ->(current, total) do
        show_progress(user_id, current, total, "Processando linha #{current} de #{total}...")
      end
    ).call

    show_import_result(user_id, result)
  rescue StandardError => e
    show_result(user_id, "❌ Erro: #{e.message}", false, true)
  ensure
    File.delete(file_path) if file_path.present? && File.exist?(file_path)
  end

  private

  def show_progress(user_id, current, total, message)
    return unless user_id

    progress = total > 0 ? ((current.to_f / total) * 100).round : 0
    html = ApplicationController.render(
      partial: "shared/import_progress",
      locals: {
        message: message,
        visible: true,
        completed: false,
        error: false,
        current: current,
        total: total,
        progress: progress
      }
    )

    ActionCable.server.broadcast("user_#{user_id}", { html: html })
  end

  def show_import_result(user_id, result)
    return unless user_id

    message_parts = []
    message_parts << "✅ #{result[:wms_imported]} tarefas WMS processadas."
    message_parts << "♻️ #{result[:refugo_imported]} registros de refugo disponibilizados para os ajudantes."

    if result[:skipped_operators].any?
      message_parts << "👤 #{result[:skipped_operators].size} nomes não vinculados a operadores"
    end

    if result[:failed_rows].any?
      message_parts << "❌ #{result[:failed_rows].size} linhas com erro"
      result[:failed_rows].first(2).each do |failed_row|
        message_parts << "• #{failed_row[:operator]}: #{failed_row[:error]}"
      end
    end

    show_detailed_result(
      user_id,
      message_parts.join("\n"),
      result[:wms_imported].zero? && result[:refugo_imported].zero?,
      result
    )
  end

  def show_detailed_result(user_id, message, error, result)
    return unless user_id

    html = ApplicationController.render(
      partial: "shared/import_progress",
      locals: {
        message: message,
        visible: true,
        completed: true,
        error: error,
        show_link: true,
        current: result[:total_rows],
        total: result[:total_rows],
        progress: 100
      }
    )

    ActionCable.server.broadcast("user_#{user_id}", { html: html })
  end

  def show_result(user_id, message, error = false, completed = true)
    return unless user_id

    html = ApplicationController.render(
      partial: "shared/import_progress",
      locals: {
        message: message,
        visible: true,
        completed: completed,
        error: error,
        show_link: true
      }
    )

    ActionCable.server.broadcast("user_#{user_id}", { html: html })
  end
end
