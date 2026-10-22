module AiAssistant
  class ErrorReport
    MESSAGES = {
      timeout: 'O Gemini demorou além do limite de espera. Tente novamente ou consulte um período menor.',
      connection: 'Não foi possível conectar ao Gemini. Tente novamente em instantes.',
      not_configured: 'A chave do Gemini não está configurada. Solicite a configuração ao administrador.',
      authentication: 'O Gemini recusou a chave ou a permissão de acesso. Solicite a revisão da configuração ao administrador.',
      quota: 'O limite de uso do Gemini foi atingido. Aguarde e tente novamente.',
      model: 'O modelo de IA configurado não está disponível. Solicite a revisão da configuração ao administrador.',
      provider: 'O serviço Gemini está indisponível neste momento. Tente novamente em instantes.',
      invalid_request: 'O Gemini recusou o formato da consulta. Informe o código abaixo ao administrador.',
      invalid_response: 'O Gemini retornou uma resposta inválida ou incompleta. Tente novamente.',
      analysis_limit: 'A análise excedeu o limite de etapas. Divida a pergunta em consultas menores.',
      internal: 'Não foi possível responder por uma falha interna do app. Informe o código abaixo ao administrador.'
    }.freeze

    attr_reader :code, :reference

    def initialize(error, context: {})
      @error, @context = error, context
      @reference = "IA-#{SecureRandom.hex(6).upcase}"
      @code = case error
              when Responder::Unavailable then error.reason
              when Faraday::TimeoutError then :timeout
              when Faraday::ConnectionFailed then :connection
              else :internal
              end
    end

    def message
      "#{MESSAGES.fetch(code, MESSAGES[:internal])} Código: #{reference}."
    end

    def log!
      frames = Array(@error.backtrace_locations).filter_map do |frame|
        path = frame.path.delete_prefix("#{Rails.root}/")
        "#{path}:#{frame.lineno}" if path.start_with?('app/')
      end.first(12)
      # Não registra mensagens de exceção, corpos HTTP, perguntas ou credenciais.
      Rails.logger.error(JSON.generate(event: 'ai_assistant_failure', reference: reference, reason: code,
        exception: @error.class.name, context: @context.slice(:job_id, :conversation_id, :message_id, :model, :tool),
        http_status: @error.respond_to?(:http_status) ? @error.http_status : nil, frames: frames))
    end
  end
end
