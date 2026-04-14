class TaskImportService
  def initialize(file, current_user)
    @file = file
    @current_user = current_user
  end

  def call
    spreadsheet = Roo::Excelx.new(@file.path)
    header = spreadsheet.row(1).map { |h| h.to_s.strip }

    create_action_plan

    rows = (2..spreadsheet.last_row).map do |i|
      Hash[[header, spreadsheet.row(i)].transpose]
    end

    prepare_buckets(rows)

    rows.each do |row|
      import_task(row)
    end

    @action_plan
  end

  private

  def create_action_plan
    name = File.basename(@file.original_filename, ".xlsx")

    @action_plan = ActionPlan.create!(
      name: name,
      user: @current_user
    )
  end

  # 🔥 AQUI ESTÁ O GANHO DE PERFORMANCE
  def prepare_buckets(rows)
    bucket_names = rows.map do |row|
      row["Nome do Bucket"] || row["Bucket Name"]
    end.compact.map(&:strip).uniq

    existing_buckets = Bucket.where(
      action_plan: @action_plan,
      name: bucket_names
    ).index_by(&:name)

    @buckets_cache = existing_buckets

    (bucket_names - existing_buckets.keys).each do |name|
      bucket = Bucket.create!(
        name: name,
        action_plan: @action_plan
      )

      @buckets_cache[name] = bucket
    end
  end

  def import_task(row)
    bucket_name =
      row["Nome do Bucket"] ||
      row["Bucket Name"]

    name = bucket_name.to_s.strip
    name = "Sem Bucket" if name.blank?

    task = Task.new(
      title: row["Nome da tarefa"],
      description: row["Descrição"],
      start_at: parse_date(row["Data de início"]),
      due_at: parse_date(row["Data de conclusão"]),
      completed: completed?(row),
      completed_at: parse_date(row["Concluído em"]),
      status: map_status(row["Progresso"]),
      creator: @current_user,
      assignee_id: @current_user.id,
      bucket: @buckets_cache[name]
    )

    task.save!
  end

  def map_status(progress)
    value = progress.to_s.downcase

    if value.include?("conclu")
      "done"
    elsif value.include?("andamento")
      "in_progress"
    else
      "pending"
    end
  end

  def completed?(row)
    row["Concluído em"].present?
  end

  def parse_date(value)
    return nil if value.blank?

    if value.is_a?(Date) || value.is_a?(Time)
      value
    else
      Date.parse(value.to_s) rescue nil
    end
  end
end