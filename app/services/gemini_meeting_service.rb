require "base64"
require "json"

class GeminiMeetingService
  ENDPOINT = "https://generativelanguage.googleapis.com/v1beta/interactions"
  MODEL = "gemini-3.6-flash"

  def initialize(meeting)
    @meeting = meeting
  end

  def call
    api_key = ENV["GEMINI_API_KEY"].presence
    raise "GEMINI_API_KEY não configurada." if api_key.blank?
    raise "O áudio da reunião não está disponível." unless @meeting.audio.attached?

    response = Faraday.post(ENDPOINT) do |request|
      request.headers["x-goog-api-key"] = api_key
      request.headers["Content-Type"] = "application/json"
      request.body = JSON.generate(payload)
      request.options.timeout = 180
      request.options.open_timeout = 15
    end

    unless response.success?
      raise "Gemini retornou #{response.status}: #{response.body.to_s.truncate(500)}"
    end

    parse_response(response.body)
  end

  private

  def payload
    {
      model: MODEL,
      input: [
        { type: "text", text: prompt },
        {
          type: "audio",
          data: Base64.strict_encode64(@meeting.audio.download),
          mime_type: @meeting.audio.content_type.to_s.split(";").first
        }
      ],
      response_format: {
        type: "text",
        mime_type: "application/json",
        schema: response_schema
      },
      generation_config: {
        temperature: 0.2
      }
    }
  end

  def prompt
    <<~PROMPT
      Você é um secretário de reuniões. Analise o áudio anexado e produza uma ata em português do Brasil.
      Não invente informações. Quando um dado não estiver claro, use uma string vazia ou uma lista vazia.
      Identifique tarefas acionáveis, mas não transforme comentários genéricos em tarefas.
      Para cada tarefa, informe um título curto, descrição, prazo no formato YYYY-MM-DD se houver,
      o nome do responsável se estiver claro e o nome do bucket se estiver claro.
      A reunião pertence ao action plan "#{@meeting.action_plan.name}".
      Retorne somente o JSON no formato solicitado.
    PROMPT
  end

  def response_schema
    {
      type: "object",
      properties: {
        transcript: { type: "string" },
        summary: { type: "string" },
        decisions: { type: "array", items: { type: "string" } },
        pending_items: { type: "array", items: { type: "string" } },
        tasks: {
          type: "array",
          items: {
            type: "object",
            properties: {
              title: { type: "string" },
              description: { type: "string" },
              due_date: { type: "string" },
              assignee_name: { type: "string" },
              bucket_name: { type: "string" }
            },
            required: %w[title description due_date assignee_name bucket_name]
          }
        }
      },
      required: %w[transcript summary decisions pending_items tasks]
    }
  end

  def parse_response(body)
    data = JSON.parse(body)
    text = data.dig("outputs", -1, "text") ||
      data.fetch("steps", []).reverse
        .flat_map { |step| step.dig("content") || [] }
        .filter_map { |content| content["text"] }
        .first
    raise "Gemini não retornou conteúdo." if text.blank?

    JSON.parse(text).slice("transcript", "summary", "decisions", "pending_items", "tasks")
  rescue JSON::ParserError => e
    raise "Resposta inválida do Gemini: #{e.message}"
  end
end
