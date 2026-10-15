require "json"

# Registra somente metadados, sem chave, prompt, áudio ou resposta da IA.
class GeminiRequest
  def self.track(model:, feature:, api_key:, user: nil, collaborator: nil)
    requested_at = Time.current
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = nil
    begin
      response = yield
    ensure
      record(model: model, feature: feature, api_key: api_key, user: user, collaborator: collaborator, response: response,
        requested_at: requested_at, duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
    end
    response
  end

  def self.record(model:, feature:, api_key:, user:, collaborator:, response:, requested_at:, duration_ms:)
    body = parse_body(response&.body)
    usage = body.is_a?(Hash) ? (body["usage"] || body["usageMetadata"] || {}) : {}
    usage = {} unless usage.is_a?(Hash)
    AiApiRequest.create!(model: model, feature: feature, user: collaborator ? nil : user, collaborator: collaborator,
      credential_fingerprint: AiApiRequest.fingerprint(api_key), requested_at: requested_at,
      duration_ms: duration_ms, http_status: response&.status,
      input_tokens: token_count(usage["total_input_tokens"] || usage["promptTokenCount"]),
      output_tokens: token_count(usage["total_output_tokens"] || usage["candidatesTokenCount"]),
      total_tokens: token_count(usage["total_tokens"] || usage["totalTokenCount"]),
      retry_at: retry_at(response, body))
  rescue StandardError => error
    # Falha de observabilidade não pode alterar a resposta nem os retries da IA.
    Rails.logger.warn("Não foi possível registrar uso da IA: #{error.class}")
  end
  private_class_method :record

  def self.parse_body(body)
    JSON.parse(body.to_s)
  rescue JSON::ParserError
    {}
  end
  private_class_method :parse_body

  def self.token_count(value)
    value if value.is_a?(Integer) && value >= 0
  end
  private_class_method :token_count

  def self.retry_at(response, body)
    return unless response&.status == 429

    delay = response.headers.to_h["retry-after"].to_s
    return Time.current + delay.to_i.seconds if delay.match?(/\A\d+\z/)
    return Time.httpdate(delay) if delay.present?

    details = body.is_a?(Hash) ? body.dig("error", "details") : nil
    retry_info = Array(details).find { |detail| detail.is_a?(Hash) && detail["@type"].to_s.end_with?("RetryInfo") }
    seconds = retry_info&.fetch("retryDelay", "").to_s
    Time.current + seconds.to_f.seconds if seconds.match?(/\A\d+(\.\d+)?s\z/)
  rescue ArgumentError
    nil
  end
  private_class_method :retry_at
end
