require "json"

class GeminiThemeService
  class InvalidColors < StandardError; end
  class Unavailable < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super({
        not_configured: "O Gemini ainda não está configurado. Confira a chave nas configurações do aplicativo.",
        timeout: "O Gemini demorou para responder. Tente gerar novamente.",
        connection: "Não foi possível conectar ao Gemini. Tente novamente em instantes.",
        authentication: "O Gemini recusou a chave de acesso. Confira a configuração do aplicativo.",
        quota: "O limite de uso do Gemini foi atingido. Aguarde um pouco e tente novamente.",
        invalid_response: "O Gemini não retornou um tema válido com as cores informadas. Tente gerar novamente.",
        provider: "Não foi possível gerar o tema agora. Tente novamente em instantes."
      }.fetch(reason))
    end
  end

  ATTRIBUTES = %w[name description base_color primary_color accent_color highlight_color extra_color decoration promotion_text].freeze
  REQUEST_TIMEOUT = 12
  TOTAL_TIMEOUT = 25

  def initialize(colors:, user:)
    @colors = parse_colors(colors)
    @user = user
  end

  def call
    api_key = ENV["GEMINI_API_KEY"].presence
    raise Unavailable.new(:not_configured) unless api_key

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + TOTAL_TIMEOUT
    models = ([AiSetting.current.primary_model] + GeminiMeetingService::DEFAULT_FALLBACK_MODELS).uniq.first(3)
    failure = Unavailable.new(:provider)
    models.each do |model|
      remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      break if remaining <= 0

      begin
        response = GeminiRequest.track(model: model, feature: "theme_generation", api_key: api_key, user: @user) do
          Faraday.post(GeminiMeetingService::ENDPOINT) do |request|
            request.headers["x-goog-api-key"] = api_key
            request.headers["Content-Type"] = "application/json"
            request.options.timeout = [REQUEST_TIMEOUT, remaining].min
            request.options.open_timeout = [5, remaining].min
            request.body = JSON.generate(payload(model))
          end
        end
      rescue Faraday::TimeoutError, Faraday::ConnectionFailed => error
        failure = Unavailable.new(error.is_a?(Faraday::TimeoutError) ? :timeout : :connection)
        next
      end

      return parse_response(response.body) if response.success?

      reason = case response.status
               when 401, 403 then :authentication
               when 429 then :quota
               when 408, 504 then :timeout
               else :provider
               end
      failure = Unavailable.new(reason)
      break unless [404, 408, 429].include?(response.status) || response.status.between?(500, 599)
    end
    raise failure
  end

  private

  def parse_colors(input)
    tokens = input.to_s.strip.split(/[\s,;]+/)
    valid = input.to_s.length <= 200 && tokens.present? && tokens.all? { |token| token.match?(/\A#?(?:[0-9a-f]{3}|[0-9a-f]{6})\z/i) }
    raise InvalidColors, "Informe de 1 a 5 cores HEX válidas, como #522D60." unless valid

    colors = tokens.map do |token|
      hex = token.delete_prefix("#").upcase
      hex = hex.chars.map { |char| char * 2 }.join if hex.length == 3
      "##{hex}"
    end.uniq
    raise InvalidColors, "Use no máximo 5 cores diferentes." unless colors.length.between?(1, 5)

    colors
  end

  def payload(model)
    {
      model: model, store: false,
      system_instruction: <<~TEXT,
        Crie um tema para o aplicativo Logia. Responda em português do Brasil, somente com o JSON solicitado.
        Distribua as cores HEX fornecidas entre base_color (barra superior), primary_color (ações),
        accent_color (destaques) e highlight_color (complemento e fundos).
        Preserve TODAS as cores fornecidas, sem mudar seus códigos. Com 4 ou 5 cores, use somente essas cores,
        cada uma exatamente uma vez. Com 1 a 3, complete uma paleta coerente de exatamente 4 cores.
        Use extra_color somente quando forem fornecidas 5 cores; nos demais casos retorne string vazia.
        Use HEX de seis dígitos com #. Prefira a cor mais escura na base e preserve bom contraste nas ações.
        Crie name com até 40 caracteres, description com até 160 e decoration com um único emoji pertinente
        (ou string vazia). Crie promotion_text curto, com até 64 caracteres, convidando a experimentar o tema.
        A inspiração pode ser a natureza ou a sensação das cores; não presuma um feriado específico sem contexto.
        Não programe divulgação ou datas. Não retorne HTML, CSS, código, URLs ou campos adicionais.
      TEXT
      input: [{ type: "text", text: JSON.generate(colors: @colors) }],
      response_format: { type: "text", mime_type: "application/json", schema: {
        type: "object", properties: ATTRIBUTES.index_with { { type: "string" } }, required: ATTRIBUTES
      } },
      generation_config: { temperature: 0.3, max_output_tokens: 1600 }
    }
  end

  def parse_response(body)
    response = JSON.parse(body)
    raise Unavailable.new(:invalid_response) unless response.is_a?(Hash)
    raise Unavailable.new(:invalid_response) if %w[failed cancelled in_progress].include?(response["status"])

    parts = Array(response["steps"]).select { |step| step.is_a?(Hash) && step["type"] == "model_output" }
      .flat_map { |step| Array(step["content"]) }.filter_map { |part| part["text"] if part.is_a?(Hash) && part["type"] == "text" }
    parts = Array(response["outputs"]).filter_map { |part| part["text"] if part.is_a?(Hash) } if parts.empty?
    data = JSON.parse(parts.join("\n"))
    raise Unavailable.new(:invalid_response) unless data.is_a?(Hash) && ATTRIBUTES.all? { |key| data[key].is_a?(String) }

    theme = ColorTheme.new(data.slice(*ATTRIBUTES))
    theme.name = available_name(theme.name)
    expected_size = @colors.length == 5 ? 5 : 4
    valid = theme.valid? && theme.palette.length == expected_size && theme.palette.uniq.length == expected_size && (@colors - theme.palette).empty?
    valid &&= theme.palette.sort == @colors.sort if @colors.length >= 4
    raise Unavailable.new(:invalid_response) unless valid

    theme.attributes.slice(*ATTRIBUTES)
  rescue JSON::ParserError, TypeError
    raise Unavailable.new(:invalid_response)
  end

  def available_name(name)
    base = name.strip
    candidate = base
    number = 1
    loop do
      key = candidate.parameterize(separator: "_")
      return candidate unless User::COLOR_THEMES.value?(key) || ColorTheme.exists?(key: key) || ColorTheme.where("LOWER(name) = ?", candidate.downcase).exists?

      number += 1
      suffix = " #{number}"
      candidate = base.first(40 - suffix.length) + suffix
    end
  end
end
