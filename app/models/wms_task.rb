class WmsTask < ApplicationRecord
  belongs_to :operator

  validates :task_code, :task_type, presence: true
  validates :duration, numericality: { greater_than_or_equal_to: 10 }

  def self.import(file)
    spreadsheet = Roo::Spreadsheet.open(file.path)
    header = spreadsheet.row(1)
    imported_count = 0
    skipped_operators = []
    failed_rows = []

    (2..spreadsheet.last_row).each do |i|
      row = Hash[[header, spreadsheet.row(i)].transpose]

      nome_operador = normalize_string(row['Usuário'])
      next if nome_operador.blank?

      # Busca o operador comparando os nomes normalizados em Ruby (não no banco)
      operator = Operator.all.find { |op| normalize_string(op.nome) == nome_operador }

      unless operator
        skipped_operators << nome_operador
        next
      end

      task = new(
        operator: operator,
        task_type: row['Tipo'],
        plate: row['Placa Carreta'],
        task_code: row['Tarefa'],
        pallet: row['Palete'],
        started_at: row['Data Última Associação'],
        ended_at: row['Data de Alteração']
      )

      task.duration = calculate_duration(task.started_at, task.ended_at)

      if task.save
        imported_count += 1
      else
        failed_rows << { row: i, error: task.errors.full_messages.join(', '), data: row }
      end
    end

    {
      imported: imported_count,
      skipped_operators: skipped_operators.uniq,
      failed_rows: failed_rows,
      total_rows: spreadsheet.last_row - 1
    }
  end

  private

  def self.normalize_string(str)
    return "" if str.nil?
    str.to_s
       .unicode_normalize(:nfd)  # Decompõe acentos (é → e + ´)
       .gsub(/[\u0300-\u036f]/, '')  # Remove os diacríticos
       .upcase
       .strip
       .gsub(/\s+/, ' ')  # Remove espaços extras
  rescue
    str.to_s.upcase.strip  # Fallback seguro
  end

  def self.calculate_duration(start_time, end_time)
    return 10 unless start_time && end_time
    duration = (end_time - start_time).to_i
    duration >= 10 ? duration : 10
  end
end
