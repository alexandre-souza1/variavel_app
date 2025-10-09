class WmsTask < ApplicationRecord
  belongs_to :operator

  validates :task_code, :task_type, presence: true
  validates :duration, numericality: { greater_than_or_equal_to: 10 }

  def self.import_from_csv_rows(rows, &progress_block)
    imported_count = 0
    skipped_operators = []
    failed_rows = []

    total_rows = rows.size

    operators_hash = Operator.all.each_with_object({}) do |op, hash|
      hash[normalize_string(op.nome)] = op.id
    end

    rows.each do |row|
      nome_operador = normalize_string(row['Usuário'].to_s)

      if nome_operador.blank?
        imported_count += 1 # conta como processada mesmo vazia
        next
      end

      operator_id = operators_hash[nome_operador]
      unless operator_id
        skipped_operators << nome_operador
        imported_count += 1 # conta como processada
        next
      end

      task = new(
        operator_id: operator_id,
        task_type: row['Tipo'],
        task_code: row['Tarefa'],
        plate: row['Placa Carreta'],
        pallet: row['Palete'],
        started_at: parse_date(row['Data Última Associação']),
        ended_at: parse_date(row['Data de Alteração'])
      )

      task.duration = calculate_duration(task.started_at, task.ended_at)

      if task.save
        imported_count += 1
      else
        failed_rows << { error: task.errors.full_messages.join(', ') }
      end

      # Reporta progresso a cada 10 registros ou no final
      if progress_block && (imported_count % 10 == 0 || imported_count == total_rows)
        progress_block.call(imported_count, total_rows)
      end
    end

    {
      imported: imported_count,
      skipped_operators: skipped_operators.uniq,
      failed_rows: failed_rows,
      total_rows: total_rows
    }
  end

  private

  def self.normalize_string(str)
    return "" if str.nil?
    str.to_s
       .unicode_normalize(:nfd)
       .gsub(/[\u0300-\u036f]/, '')
       .upcase
       .strip
       .gsub(/\s+/, ' ')
  rescue
    str.to_s.upcase.strip
  end

  def self.calculate_duration(start_time, end_time)
    return 10 unless start_time && end_time
    duration = (end_time - start_time).to_i
    duration >= 10 ? duration : 10
  end

  def self.parse_date(date_string)
    return nil if date_string.blank?

    if date_string.is_a?(String)
      clean_date = date_string.gsub(/[\r\n\t]/, '').strip
      DateTime.parse(clean_date) rescue nil
    else
      date_string
    end
  end
end
