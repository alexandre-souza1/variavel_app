require "csv"
require "digest"

class SharedTasksImportService
  def initialize(file:, user: nil, progress: nil, original_filename: nil)
    @file_path = file.respond_to?(:path) ? file.path : file.to_s
    @original_filename = original_filename.presence || if file.respond_to?(:original_filename)
                           file.original_filename
                         else
                           File.basename(@file_path)
                         end
    @user = user
    @progress = progress
  end

  def call
    raise ArgumentError, "Arquivo de tarefas não encontrado." unless File.exist?(@file_path)

    rows = csv_rows
    import = prepare_import
    total_rows = rows.size
    wms_imported = 0
    refugo_imported = 0
    skipped_rows = 0
    skipped_operators = []
    failed_rows = []

    operators_by_key = Operator.all.each_with_object({}) do |operator, hash|
      hash[normalize_key(operator.nome)] = operator.id
    end

    rows.each_with_index do |row, index|
      report_progress(index + 1, total_rows)

      name = text(row, "Usuário", "Usuario")
      if name.blank?
        skipped_rows += 1
        next
      end

      task_type = text(row, "Tipo")
      source_key = row_source_key(row)
      operator_id = operators_by_key[normalize_key(name)]
      row_processed = false

      if operator_id
        task = find_wms_task(source_key, operator_id, row)
        task.assign_attributes(wms_attributes(row, operator_id, source_key, import))

        if task.save
          wms_imported += 1 if task.previously_new_record?
          row_processed = true
        else
          failed_rows << { row_data: row.to_h, operator: name, error: task.errors.full_messages.join(", ") }
        end
      elsif !refugo_type?(task_type)
        skipped_operators << name
      end

      if refugo_type?(task_type)
        refugo = AzRvTask.find_or_initialize_by(source_key: source_key)
        refugo.assign_attributes(az_refugo_attributes(row, name, source_key, import))

        if refugo.save
          refugo_imported += 1 if refugo.previously_new_record?
          row_processed = true
        else
          failed_rows << { row_data: row.to_h, operator: name, error: refugo.errors.full_messages.join(", ") }
        end
      end

      skipped_rows += 1 unless row_processed
    end

    import.update!(
      status: "completed",
      rows_imported: total_rows,
      rows_skipped: skipped_rows,
      error_message: nil
    )

    {
      import: import,
      imported: wms_imported,
      wms_imported: wms_imported,
      refugo_imported: refugo_imported,
      skipped_operators: skipped_operators.uniq,
      failed_rows: failed_rows,
      total_rows: total_rows
    }
  rescue StandardError => e
    import&.update_columns(status: "failed", error_message: e.message, updated_at: Time.current)
    raise
  end

  private

  def prepare_import
    digest = Digest::SHA256.file(@file_path).hexdigest
    import = AzRvImport.find_or_initialize_by(source_type: "tasks", file_digest: digest)
    import.assign_attributes(
      original_filename: @original_filename,
      status: "processing",
      user: @user
    )
    import.save!
    import
  end

  def find_wms_task(source_key, operator_id, row)
    existing = WmsTask.find_by(source_key: source_key)
    return existing if existing

    # Compatibilidade com tarefas importadas anteriormente pelo WMS, antes
    # da importação compartilhada possuir source_key.
    WmsTask.find_by(
      operator_id: operator_id,
      task_type: text(row, "Tipo"),
      task_code: text(row, "Tarefa"),
      started_at: parse_datetime(text(row, "Data Última Associação", "Data Ultima Associacao")),
      ended_at: parse_datetime(text(row, "Data de Alteração", "Data de Alteracao"))
    ) || WmsTask.new
  end

  def wms_attributes(row, operator_id, source_key, import)
    started_at = parse_datetime(text(row, "Data Última Associação", "Data Ultima Associacao"))
    ended_at = parse_datetime(text(row, "Data de Alteração", "Data de Alteracao"))

    {
      operator_id: operator_id,
      task_type: text(row, "Tipo"),
      task_code: text(row, "Tarefa"),
      plate: text(row, "Placa Carreta"),
      pallet: text(row, "Palete"),
      started_at: started_at,
      ended_at: ended_at,
      duration: calculate_duration(started_at, ended_at),
      source_key: source_key,
      az_rv_import_id: import.id
    }
  end

  def az_refugo_attributes(row, name, source_key, import)
    {
      source_key: source_key,
      warehouse: text(row, "Armazém", "Armazem"),
      map_code: text(row, "Mapa"),
      task_number: text(row, "Tarefa"),
      horse_plate: text(row, "Placa Cavalo"),
      trailer_plate: text(row, "Placa Carreta"),
      origin: text(row, "Origem"),
      destination: text(row, "Destino"),
      pallet: text(row, "Palete"),
      priority: text(row, "Prioridade"),
      status: text(row, "Status"),
      task_type: text(row, "Tipo"),
      employee_name: name,
      employee_key: normalize_key(name),
      created_at_source: parse_datetime(text(row, "Data de Criação", "Data de Criacao")),
      associated_at: parse_datetime(text(row, "Data Última Associação", "Data Ultima Associacao")),
      changed_at: parse_datetime(text(row, "Data de Alteração", "Data de Alteracao")),
      released_at: parse_datetime(text(row, "Data de Liberação", "Data de Liberacao")),
      completed_task: text(row, "Concluída Task", "Concluida Task"),
      az_rv_import_id: import.id
    }
  end

  def row_source_key(row)
    Digest::SHA256.hexdigest(row.fields.map { |value| value.to_s.strip }.join("\u001f"))
  end

  def refugo_type?(value)
    value.to_s.strip.casecmp("Blitz Refugo").zero?
  end

  def csv_rows
    CSV.parse(csv_content, headers: true, col_sep: ";", liberal_parsing: true)
  end

  def csv_content
    raw_content = File.binread(@file_path)
    raw_content = raw_content.byteslice(3..-1) if raw_content.start_with?("\xEF\xBB\xBF".b)

    raw_content.dup.force_encoding(Encoding::UTF_8).encode(Encoding::UTF_8)
  rescue Encoding::InvalidByteSequenceError, Encoding::UndefinedConversionError
    raw_content.force_encoding(Encoding::ISO_8859_1).encode(Encoding::UTF_8)
  end

  def text(row, *headers)
    headers.each do |header|
      value = row[header]
      return value.to_s.strip.presence if value.present?
    end
    nil
  end

  def parse_datetime(value)
    return if value.blank?

    DateTime.parse(value).to_time
  rescue ArgumentError
    Time.zone.parse(value)
  rescue StandardError
    nil
  end

  def calculate_duration(started_at, ended_at)
    return 10 unless started_at && ended_at

    duration = (ended_at - started_at).to_i
    duration >= 10 ? duration : 10
  end

  def normalize_key(value)
    value.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
        .downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  def report_progress(current, total)
    return unless @progress

    @progress.call(current, total)
  end
end
