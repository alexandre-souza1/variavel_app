class GeminiUsageDashboard
  PACIFIC_ZONE = "America/Los_Angeles"
  STAT_COLUMNS = %i[attempts accepted rate_limited input_tokens output_tokens missing_input missing_output].freeze
  AGGREGATES = [
    "COUNT(*)",
    "COUNT(*) FILTER (WHERE http_status BETWEEN 200 AND 299)",
    "COUNT(*) FILTER (WHERE http_status = 429)",
    "COALESCE(SUM(input_tokens) FILTER (WHERE http_status BETWEEN 200 AND 299), 0)",
    "COALESCE(SUM(output_tokens) FILTER (WHERE http_status BETWEEN 200 AND 299), 0)",
    "COUNT(*) FILTER (WHERE http_status BETWEEN 200 AND 299 AND input_tokens IS NULL)",
    "COUNT(*) FILTER (WHERE http_status BETWEEN 200 AND 299 AND output_tokens IS NULL)"
  ].map { |sql| Arel.sql(sql) }.freeze

  attr_reader :now, :day_start, :day_end, :setting

  def initialize(setting, now: Time.current)
    @setting = setting
    @now = now
    @day_start = now.in_time_zone(PACIFIC_ZONE).beginning_of_day
    @day_end = @day_start.advance(days: 1)
    @requests = AiApiRequest.where(credential_fingerprint: AiApiRequest.current_credential_fingerprint)
  end

  def cards
    @cards ||= begin
      daily_scope = @requests.where(requested_at: day_start..now)
      daily = stats(daily_scope)
      minute = stats(@requests.where(requested_at: (now - 1.minute)..now))
      latest = @requests.where("requested_at <= ?", now)
        .select("DISTINCT ON (model) model, http_status, requested_at, retry_at")
        .order(:model, requested_at: :desc, id: :desc).index_by(&:model)
      features = daily_scope.successful.group(:model, :feature).count

      AiSetting::MODELS.map do |label, model|
        day = daily.fetch(model, empty_stats)
        recent = minute.fetch(model, empty_stats)
        limits = setting.model_limits.fetch(model, {})
        {
          model: model, label: label, primary: setting.primary_model == model,
          latest: latest[model], daily: day,
          features: AiApiRequest::FEATURES.to_h { |key, name| [name, features.fetch([model, key], 0)] },
          metrics: [
            metric("Requisições / min", recent[:accepted], limits["rpm"]),
            metric("Tokens de entrada / min", recent[:missing_input].zero? ? recent[:input_tokens] : nil, limits["tpm"]),
            metric("Requisições / dia", day[:accepted], limits["rpd"])
          ]
        }
      end
    end
  end

  def tracked_since
    @tracked_since ||= @requests.minimum(:requested_at) || setting.usage_tracking_started_at
  end

  private

  def stats(scope)
    scope.group(:model).pluck(:model, *AGGREGATES).to_h do |model, *values|
      [model, STAT_COLUMNS.zip(values.map(&:to_i)).to_h]
    end
  end

  def empty_stats
    STAT_COLUMNS.index_with(0)
  end

  def metric(label, used, limit)
    # Durante uma edição inválida, não calcula com campos ainda não normalizados.
    limit = nil unless limit.is_a?(Integer) && limit >= 0
    { label: label, used: used, limit: limit, remaining: !limit.nil? && !used.nil? ? [limit - used, 0].max : nil }
  end
end
