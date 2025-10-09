class WmsTaskImportJob < ApplicationJob
  queue_as :default

  def perform(file_path, user_id = nil)
    file_path = file_path.to_s

    unless File.exist?(file_path)
      show_result(user_id, "❌ Arquivo não encontrado", false, true)
      return
    end

    begin
      csv_content = File.read(file_path)
      csv = CSV.parse(csv_content, headers: true, encoding: 'UTF-8', col_sep: ';')

      total_rows = csv.size

      # Mostra progresso inicial
      show_progress(user_id, 0, total_rows, "Iniciando importação...")

      # Importa os dados com progresso
      result = import_data_with_progress(csv, user_id)

      # Mostra resultado final
      show_import_result(user_id, result)

    rescue => e
      show_result(user_id, "❌ Erro: #{e.message}", false, true)
    ensure
      File.delete(file_path) if File.exist?(file_path)
    end
  end

  private

  def import_data_with_progress(csv, user_id)
    imported_count = 0
    skipped_operators = []
    failed_rows = []

    operators_hash = Operator.all.each_with_object({}) do |op, hash|
      hash[WmsTask.normalize_string(op.nome)] = op.id
    end

    csv.each_with_index do |row, index|
      nome_operador = WmsTask.normalize_string(row['Usuário'].to_s)

      # Atualiza progresso a cada 10 linhas ou no final
      if (index % 10 == 0) || (index == csv.size - 1)
        progress = ((index + 1).to_f / csv.size * 100).round
        show_progress(user_id, index + 1, csv.size, "Processando linha #{index + 1} de #{csv.size}...")
      end

      if nome_operador.blank?
        imported_count += 1
        next
      end

      operator_id = operators_hash[nome_operador]
      unless operator_id
        skipped_operators << nome_operador
        imported_count += 1
        next
      end

      task = WmsTask.new(
        operator_id: operator_id,
        task_type: row['Tipo'],
        task_code: row['Tarefa'],
        plate: row['Placa Carreta'],
        pallet: row['Palete'],
        started_at: WmsTask.parse_date(row['Data Última Associação']),
        ended_at: WmsTask.parse_date(row['Data de Alteração'])
      )

      task.duration = WmsTask.calculate_duration(task.started_at, task.ended_at)

      if task.save
        imported_count += 1
      else
        failed_rows << {
          row_data: row.to_h,
          error: task.errors.full_messages.join(', '),
          operator: nome_operador
        }
      end
    end

    {
      imported: imported_count,
      skipped_operators: skipped_operators.uniq,
      failed_rows: failed_rows,
      total_rows: csv.size
    }
  end

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

    imported = result[:imported]
    skipped_operators = result[:skipped_operators]
    failed_rows = result[:failed_rows]
    total = result[:total_rows]

    # Construir mensagem detalhada
    message_parts = []

    if imported > 0
      message_parts << "✅ #{imported} tarefas importadas com sucesso."
    else
      message_parts << "❌ Nenhuma tarefa importada."
    end

    # Detalhes de operadores não encontrados
    if skipped_operators.any?
      message_parts << "👤 #{skipped_operators.size} operadores não encontrados"
      if skipped_operators.size <= 3
        message_parts << "Não localizados: #{skipped_operators.join(', ')}"
      end
    end

    # Detalhes de erros
    if failed_rows.any?
      message_parts << "❌ #{failed_rows.size} linhas com erro"
      failed_rows.first(2).each do |failed_row|
        message_parts << "• #{failed_row[:operator]}: #{failed_row[:error]}"
      end
      message_parts << "• ... mais #{failed_rows.size - 2} erros" if failed_rows.size > 2
    end

    message = message_parts.join("\n")
    error = imported == 0

    show_detailed_result(user_id, message, error, result)
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
        current: result[:imported],
        total: result[:total_rows],
        progress: 100
      }
    )

    ActionCable.server.broadcast("user_#{user_id}", { html: html })
  end

  def show_result(user_id, message, error = false)
    return unless user_id

    html = ApplicationController.render(
      partial: "shared/import_progress",
      locals: {
        message: message,
        visible: true,
        completed: true,
        error: error,
        show_link: true
      }
    )

    ActionCable.server.broadcast("user_#{user_id}", { html: html })
  end
end
