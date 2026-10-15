# Relatório agregado: consulta metadados de chamadas e nomes dos cadastros.
# Não consulta conversas, perguntas, respostas ou dados de autenticação.
class GeminiUsageReport
  IDENTITY_COLUMNS = %i[user_id collaborator_type collaborator_id].freeze
  IDENTITY_ORDER = "user_id ASC NULLS LAST, collaborator_type ASC NULLS LAST, collaborator_id ASC NULLS LAST".freeze
  PERIODS = { "7" => "Últimos 7 dias", "30" => "Últimos 30 dias", "90" => "Últimos 90 dias" }.freeze
  METRICS = { "calls" => "Chamadas aceitas", "input_tokens" => "Tokens de entrada informados" }.freeze

  attr_reader :now, :start_at, :period, :metric, :model, :feature

  def initialize(now: Time.current, period: nil, metric: nil, model: nil, feature: nil)
    @now = now
    @period = PERIODS.key?(period.to_s) ? period.to_s : "7"
    @metric = METRICS.key?(metric) ? metric : "calls"
    @model = model if AiSetting::MODELS.value?(model)
    @feature = feature if AiApiRequest::FEATURES.key?(feature)
    @start_at = now.in_time_zone.beginning_of_day - (@period.to_i - 1).days
    @scope = AiApiRequest.where(credential_fingerprint: AiApiRequest.current_credential_fingerprint, requested_at: @start_at..now)
    @scope = @scope.where(model: @model) if @model
    @scope = @scope.where(feature: @feature) if @feature
  end

  def filters
    { period: period, metric: metric, model: model, feature: feature }.compact
  end

  def summary
    @summary ||= begin
      values = @scope.pluck(*GeminiUsageDashboard::AGGREGATES).first.map(&:to_i)
      GeminiUsageDashboard::STAT_COLUMNS.zip(values).to_h.merge(
        active_users: @scope.successful.where.not(user_id: nil)
          .or(@scope.successful.where.not(collaborator_id: nil)).group(*IDENTITY_COLUMNS).count.length,
        unattributed: @scope.where(user_id: nil, collaborator_id: nil).count
      )
    end
  end

  def daily_series
    return [] if summary[:accepted].zero?

    grouped = @scope.successful.group(:feature).group_by_day(:requested_at, time_zone: Time.zone.name, range: start_at..now)
    values = metric == "calls" ? grouped.count : grouped.sum(:input_tokens)
    AiApiRequest::FEATURES.map do |key, label|
      { name: label, data: (start_at.to_date..now.in_time_zone.to_date).to_h do |date|
        [I18n.l(date, format: "%d/%m"), values.fetch([key, date], 0).to_i]
      end }
    end
  end

  def model_data
    return {} if summary[:accepted].zero?

    grouped = @scope.successful.group(:model)
    values = metric == "calls" ? grouped.count : grouped.sum(:input_tokens)
    keys = model ? [model] : (AiSetting::MODELS.values | values.keys)
    keys.to_h { |key| [AiSetting::MODELS.key(key) || key, values.fetch(key, 0).to_i] }
  end

  def feature_data
    counts = @scope.successful.group(:feature).count
    (AiApiRequest::FEATURES.keys | counts.keys).filter_map do |key|
      [AiApiRequest::FEATURES[key] || "Outro recurso", counts[key]] if counts.fetch(key, 0).positive?
    end.to_h
  end

  def user_chart
    expression = metric == "calls" ? "COUNT(*)" : "COALESCE(SUM(input_tokens), 0)"
    data = @scope.successful.group(*IDENTITY_COLUMNS).order(Arel.sql("#{expression} DESC"), Arel.sql(IDENTITY_ORDER))
      .limit(10).pluck(*IDENTITY_COLUMNS, Arel.sql(expression))
    names = identity_names(data.map { |row| row.first(3) })
    labels = data.map { |row| identity_label(row.first(3), names) }
    data.each_with_index.to_h do |row, index|
      key = row.first(3)
      label = labels[index]
      label = "#{label} · #{identity_kind(key)} ##{key[0] || key[2]}" if labels.count(label) > 1
      [label, row.last.to_i]
    end
  end

  def users(query: nil, page: nil)
    scope = @scope
    if query.present?
      pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.to_s.strip.first(100))}%"
      matches = [scope.where(user_id: User.where("name ILIKE ?", pattern).select(:id))]
      collaborator_models.each do |klass|
        matches << scope.where(collaborator_type: klass.name,
          collaborator_id: klass.where("nome ILIKE ?", pattern).select(:id))
      end
      scope = matches.reduce(:or)
    end
    total = scope.group(*IDENTITY_COLUMNS).count.length
    pages = [(total / 20.0).ceil, 1].max
    current = page.to_i.clamp(1, pages)
    aggregates = scope.group(*IDENTITY_COLUMNS)
      .order(Arel.sql("COUNT(*) FILTER (WHERE http_status BETWEEN 200 AND 299) DESC"), Arel.sql(IDENTITY_ORDER))
      .limit(20).offset((current - 1) * 20)
      .pluck(*IDENTITY_COLUMNS, *GeminiUsageDashboard::AGGREGATES, Arel.sql("MAX(requested_at)"),
        Arel.sql("AVG(duration_ms) FILTER (WHERE http_status BETWEEN 200 AND 299)"))
    keys = aggregates.map { |row| row.first(3) }
    names = identity_names(keys)
    selected = keys.reduce(scope.successful.none) do |result, key|
      result.or(scope.successful.where(IDENTITY_COLUMNS.zip(key).to_h))
    end
    features = selected.group(*IDENTITY_COLUMNS, :feature).count
    rows = aggregates.map do |user_id, collaborator_type, collaborator_id, *values|
      key = [user_id, collaborator_type, collaborator_id]
      duration = values.pop
      latest = values.pop
      data = GeminiUsageDashboard::STAT_COLUMNS.zip(values.map(&:to_i)).to_h
      data.merge(id: user_id || collaborator_id, label: identity_label(key, names), kind: identity_kind(key), latest: latest,
        average_seconds: duration && (duration.to_f / 1000).round(1),
        features: AiApiRequest::FEATURES.to_h { |feature, label| [label, features.fetch([*key, feature], 0)] })
    end
    { rows: rows, total: total, page: current, pages: pages }
  end

  private

  def collaborator_models
    PublicVariableIdentity::PROFILES.values.uniq
  end

  def identity_names(keys)
    names = User.where(id: keys.filter_map(&:first)).pluck(:id, :name).to_h { |id, name| [[id, nil, nil], name] }
    collaborator_models.each do |klass|
      ids = keys.filter_map { |key| key[2] if key[1] == klass.name }
      next if ids.empty?

      klass.where(id: ids).pluck(:id, :nome).each { |id, name| names[[nil, klass.name, id]] = name }
    end
    names
  end

  def identity_label(key, names)
    names[key].presence || if key[1]
      "Colaborador ##{key[2]} (cadastro indisponível)"
    elsif key[0]
      "Usuário ##{key[0]}"
    else
      "Sem usuário associado"
    end
  end

  def identity_kind(key)
    return "Conta do sistema" if key[0]
    return unless key[1]

    profile = PublicVariableIdentity::PROFILES.find { |_profile, klass| klass.name == key[1] }&.first
    PublicVariableIdentity::LABELS[profile] || "Colaborador"
  end
end
