module AiAssistant
  class AutomationWizard
    def initialize(user:, conversation:, request_token:)
      @user, @conversation, @request_token = user, conversation, request_token
    end

    def read
      change({})
    end

    def change(patch, reset: false)
      raise ActionDraft::Forbidden, "A montagem precisa ocorrer na sua conversa ativa." unless @conversation&.user_id == @user.id && @request_token.present?
      @conversation.with_lock do
        raise ActionDraft::Stale, "Esta resposta não está mais em andamento. Envie uma nova mensagem." unless @conversation.request_token == @request_token
        state = @conversation.automation_setup
        next {} if state.blank? && patch.empty? && !reset
        valid = state["access"] == access && state["expires_at"].to_s > Time.current.iso8601
        if !valid && state.present? && patch.empty? && !reset
          @conversation.update!(automation_setup: {})
          next({ expired: true, note: "A montagem anterior expirou ou o acesso mudou. Recomece com as opções atuais." })
        end
        previous = !reset && valid ? state.fetch("configuration", {}) : {}
        if patch["source_key"] && patch["source_key"] != previous["source_key"]
          previous = previous.except("filters", "operation")
          previous = previous.except("period") if patch["source_key"] == "fleet" && !previous["period"].in?(%w[today yesterday])
        end
        if patch["filters"].is_a?(Hash)
          previous = previous.deep_dup
          previous["filters"]&.delete("budget_category_id") if patch["filters"].key?("budget_category_ids")
          previous["filters"]&.delete("budget_category_ids") if patch["filters"].key?("budget_category_id")
        end
        previous = previous.except("action_config") if patch["action_key"] && patch["action_key"] != previous["action_key"]
        if patch["action_key"] == "update_indicator" && previous["period"] == "all"
          previous = previous.except("period")
        end
        if patch.dig("action_config", "routine_template_id") && patch.dig("action_config", "routine_template_id").to_s != previous.dig("action_config", "routine_template_id").to_s
          previous = previous.deep_dup
          previous["action_config"]&.delete("routine_indicator_id")
        end
        combined = previous.deep_merge(patch)
        definition = AutomationDefinition.new(user: @user.reload, arguments: combined)
        complete = definition.missing_fields.empty?
        definition.rule if complete
        unless patch.empty? && !reset
          @conversation.update!(automation_setup: { configuration: definition.data, access: access, expires_at: 2.hours.from_now.iso8601 })
        end
        { in_progress: true, configuration: definition.data, ready: complete, missing_fields: definition.missing_fields,
          next_question: definition.next_question,
          note: "Montagem privada da conversa. Nenhuma automação foi salva, ativada ou executada. Pergunte somente o próximo dado necessário e use prepare_automation quando estiver pronta." }
      end
    end

    private

    def access
      { "role" => @user.role, "sector" => @user.sector }
    end
  end
end
