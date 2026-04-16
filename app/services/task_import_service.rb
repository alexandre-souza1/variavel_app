class TaskImportService
  # Constantes para evitar strings mágicas
  BUCKET_NAME_KEYS = ["Nome do Bucket", "Bucket Name"].freeze
  LABEL_KEYS = ["Rótulos", "Labels"].freeze
  CHECKLIST_KEYS = ["Itens da lista de verificação", "Checklist items"].freeze

  def initialize(file, current_user)
    @file = file
    @current_user = current_user
  end

  def call
    rows = parse_spreadsheet
    create_action_plan
    prepare_buckets(rows)
    prepare_labels(rows)

    rows.each { |row| import_task(row) }

    @action_plan
  end

  private

  def parse_spreadsheet
    spreadsheet = Roo::Excelx.new(@file.path)
    header = spreadsheet.row(1).map { |h| h.to_s.strip }

    (2..spreadsheet.last_row).map do |i|
      Hash[[header, spreadsheet.row(i)].transpose]
    end
  end

  def create_action_plan
    name = File.basename(@file.original_filename, ".xlsx")
    @action_plan = ActionPlan.create!(name: name, user: @current_user)
  end

  def prepare_buckets(rows)
    bucket_names = extract_bucket_names(rows)

    existing_buckets = Bucket.where(
      action_plan: @action_plan,
      name: bucket_names
    ).index_by(&:name)

    missing_names = bucket_names - existing_buckets.keys

    missing_names.each do |name|
      bucket = Bucket.create!(name: name, action_plan: @action_plan)
      existing_buckets[name] = bucket
    end

    @buckets_cache = existing_buckets
  end

  def prepare_labels(rows)
    label_names = extract_label_names(rows)
    return if label_names.empty?

    existing_labels = Label.where(
      name: label_names,
      action_plan: @action_plan
    ).index_by(&:name)

    missing_names = label_names - existing_labels.keys

    if missing_names.any?
      Label.insert_all(
        missing_names.map { |name| label_attributes(name) }
      )
    end

    @labels_cache = Label.where(
      name: label_names,
      action_plan: @action_plan
    ).index_by(&:name)
  end

  def import_task(row)
    task = Task.new(task_attributes(row))

    if task.save
      associate_labels(task, row)
      create_tasklist(task, row)
    else
      Rails.logger.error "❌ Erro ao salvar task: #{task.errors.full_messages}"
    end

    task
  end

  # Métodos auxiliares de extração
  def extract_bucket_names(rows)
    rows.map { |row| find_value(row, BUCKET_NAME_KEYS) }
        .compact.map(&:strip).uniq
  end

  def extract_label_names(rows)
    rows.flat_map { |row| parse_labels(row) }.uniq.compact
  end

  def parse_labels(row)
    label_string = find_value(row, LABEL_KEYS)
    return [] if label_string.blank?

    label_string.to_s.split(";").map(&:strip).reject(&:blank?)
  end

  def parse_checklist_items(row)
    checklist_string = find_value(row, CHECKLIST_KEYS)
    return [] if checklist_string.blank?

    checklist_string.to_s.split(";").map(&:strip).reject(&:blank?)
  end

  def find_value(row, keys)
    keys.each { |key| return row[key] if row[key].present? }
    nil
  end

  # Métodos de construção de atributos
  def label_attributes(name)
    {
      name: name,
      action_plan_id: @action_plan.id,
      color: random_color,
      created_at: Time.current,
      updated_at: Time.current
    }
  end

  def task_attributes(row)
    {
      title: row["Nome da tarefa"],
      description: row["Descrição"],
      start_at: parse_date(row["Data de início"]),
      due_at: parse_date(row["Data de conclusão"]),
      completed: row["Concluído em"].present?,
      completed_at: parse_date(row["Concluído em"]),
      status: map_status(row["Progresso"]),
      creator: @current_user,
      assignee_id: @current_user.id,
      bucket: find_bucket(row)
    }
  end

  def find_bucket(row)
    bucket_name = find_value(row, BUCKET_NAME_KEYS).to_s.strip
    bucket_name = "Sem Bucket" if bucket_name.blank?
    @buckets_cache[bucket_name]
  end

  def associate_labels(task, row)
    label_names = parse_labels(row)
    return if label_names.empty?

    labels = label_names.map { |name| @labels_cache[name] }.compact
    task.labels << labels if labels.any?
  end

  def create_tasklist(task, row)
    items = parse_checklist_items(row)
    return if items.empty?                     # sem itens, não precisa fazer nada (a tasklist vazia já existe)

    # Use a tasklist existente (criada pelo callback) ou crie uma nova
    tasklist = task.tasklist || task.create_tasklist(title: "Checklist")

    # Evita duplicar itens se a planilha for reimportada
    return if tasklist.tasklist_items.any?

    TasklistItem.insert_all(
      items.map do |item|
        {
          content: item,
          completed: false,
          tasklist_id: tasklist.id,
          created_at: Time.current,
          updated_at: Time.current
        }
      end
    )
  end

  # Métodos utilitários
  def map_status(progress)
    value = progress.to_s.downcase

    case value
    when /conclu/ then "done"
    when /andamento/ then "in_progress"
    else "pending"
    end
  end

  def parse_date(value)
    return nil if value.blank?
    return value if value.is_a?(Date) || value.is_a?(Time)

    Date.parse(value.to_s) rescue nil
  end

  def random_color
    "##{SecureRandom.hex(3).upcase}"
  end
end
