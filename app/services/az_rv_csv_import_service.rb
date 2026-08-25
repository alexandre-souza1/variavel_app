require "csv"
require "digest"

class AzRvCsvImportService
  Result = Struct.new(:imports, keyword_init: true)

  def initialize(user:, points_file: nil, tasks_file: nil, ondemand_file: nil, points_reference_date: nil)
    @user = user
    @points_file = points_file
    @tasks_file = tasks_file
    @ondemand_file = ondemand_file
    @points_reference_date = points_reference_date
  end

  def call
    raise ArgumentError, "Selecione pelo menos um arquivo CSV." unless files_present?
    if @points_file.present? && @points_reference_date.blank?
      raise ArgumentError, "Informe a data de referência do arquivo de pontos."
    end

    imports = []
    imports << import_points if @points_file.present?
    imports << import_tasks if @tasks_file.present?
    imports << import_ondemand if @ondemand_file.present?
    Result.new(imports: imports)
  end

  private

  def files_present?
    @points_file.present? || @tasks_file.present? || @ondemand_file.present?
  end

  def import_points
    import = prepare_import("points", @points_file)
    return import if import.status == "completed" && import.persisted?

    rows = csv_rows(@points_file)
    records = rows.filter_map do |row|
      name = text(row, "Usuário", "Usuario")
      next if name.blank?

      {
        employee_name: name,
        employee_key: normalize_key(name),
        reference_date: @points_reference_date,
        credits: decimal(row, "Créditos", "Creditos"),
        debits: decimal(row, "Débitos", "Debitos"),
        total_points: decimal(row, "Total"),
        reported_value: decimal(row, "Valor"),
        az_rv_import_id: import.id,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    result = AzRvPoint.upsert_all(records, unique_by: :index_az_rv_points_on_employee_key_and_reference_date) if records.any?
    finish_import(import, result ? result.rows.length : 0, skipped: rows.length - (result ? result.rows.length : 0))
  rescue StandardError => e
    fail_import(import, e) if import
    raise
  end

  def import_tasks
    SharedTasksImportService.new(file: @tasks_file, user: @user).call[:import]
  end

  def import_ondemand
    import = prepare_import("ondemand", @ondemand_file)
    return import if import.status == "completed" && import.persisted?

    rows = csv_rows(@ondemand_file)
    records = rows.filter_map do |row|
      name = text(row, "Usuário", "Usuario")
      next if name.blank?

      raw_values = row.fields.map { |value| value.to_s.strip }.join("\u001f")
      {
        source_key: Digest::SHA256.hexdigest(raw_values),
        warehouse: text(row, "Armazém", "Armazem"),
        activity: text(row, "Atividade"),
        activity_code: text(row, "Código", "Codigo"),
        address: text(row, "Endereço", "Endereco"),
        task_number: text(row, "Tarefa"),
        employee_name: name,
        employee_key: normalize_key(name),
        created_at_source: parse_datetime(text(row, "Criação", "Criacao")),
        associated_at: parse_datetime(text(row, "Associação", "Associacao")),
        finalized_at: parse_datetime(text(row, "Finalização", "Finalizacao")),
        validation_status: text(row, "Validação", "Validacao"),
        task_status: text(row, "Status Tarefa"),
        observation: text(row, "Observação", "Observacao"),
        plate: text(row, "Placa"),
        vehicle_type: text(row, "Tipo de veículo", "Tipo de veiculo"),
        transport_type: text(row, "Tipo de transporte"),
        az_rv_import_id: import.id,
        created_at: Time.current,
        updated_at: Time.current
      }
    end

    result = AzRvOnDemandActivity.insert_all(records, unique_by: :index_az_rv_on_demand_activities_on_source_key) if records.any?
    finish_import(import, result ? result.rows.length : 0, skipped: rows.length - (result ? result.rows.length : 0))
  rescue StandardError => e
    fail_import(import, e) if import
    raise
  end

  def prepare_import(source_type, file)
    digest = Digest::SHA256.file(file.path).hexdigest
    existing = AzRvImport.find_by(source_type: source_type, file_digest: digest)
    if existing&.status == "completed"
      same_reference_date = source_type != "points" || existing.reference_date == @points_reference_date
      return existing if same_reference_date
    end

    existing&.destroy!
    AzRvImport.create!(
      source_type: source_type,
      reference_date: source_type == "points" ? @points_reference_date : nil,
      original_filename: file.original_filename,
      file_digest: digest,
      status: "processing",
      user: @user
    )
  end

  def finish_import(import, count, skipped: 0)
    import.update!(status: "completed", rows_imported: count, rows_skipped: skipped, error_message: nil)
    import
  end

  def fail_import(import, error)
    import.update_columns(status: "failed", error_message: error.message, updated_at: Time.current)
  end

  def csv_rows(file)
    CSV.read(file.path, headers: true, col_sep: ";", encoding: "bom|utf-8", liberal_parsing: true)
  end

  def text(row, *headers)
    headers.each do |header|
      value = row[header]
      return value.to_s.strip.presence if value.present?
    end
    nil
  end

  def decimal(row, *headers)
    value = text(row, *headers).to_s.gsub(/\s+/, "")
    return 0 if value.blank?

    normalized = if value.include?(",")
                   value.delete(".").tr(",", ".")
                 else
                   value
                 end
    BigDecimal(normalized)
  rescue ArgumentError
    0
  end

  def parse_datetime(value)
    return if value.blank?

    DateTime.strptime(value, "%d/%m/%Y %H:%M:%S").to_time
  rescue ArgumentError
    Time.zone.parse(value)
  rescue StandardError
    nil
  end

  def normalize_key(value)
    value.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
        .downcase.gsub(/[^a-z0-9]+/, " ").strip
  end
end
