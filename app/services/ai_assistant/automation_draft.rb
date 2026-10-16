module AiAssistant
  class AutomationDraft < ActionDraft
    def initialize(user:, arguments:)
      @user, @kind = user, "create_automation"
      @definition = AutomationDefinition.new(user: user, arguments: arguments)
      @rule = @definition.rule
      @payload = @definition.data
      build_preview
    end

    def simulation
      result = Automations::Preview.call(@rule)
      unless result[:result][:available]
        return { available: false, reason: "Não há dados da origem neste período. A ação será preservada.", note: result[:result][:note] }
      end
      { available: true, value: result[:result][:value].to_s("F"), count: result[:result][:count],
        from: result[:period].start_date, to: result[:period].end_date,
        condition_met: result[:condition_met], destination: result[:destination], note: result[:result][:note] }
    rescue Automations::Invalid => error
      { available: false, reason: error.message, note: "A regra pode ser salva. Quando executada, registrará ausência de dados ou destino enquanto esta situação persistir." }
    end

    def execute!(request_id:)
      # Confirmation only saves the configured rule. Never runs its action now.
      @rule.save!
      { type: "automation_rule", id: @rule.id, enabled: @rule.enabled?,
        label: "Abrir automação", path: routes.automation_rule_path(@rule) }
    end

    private

    def build_preview
      labels = Object.new.extend(AutomationRulesHelper)
      details = [detail("Origem", labels.automation_source_label(@rule)), detail("Filtros", labels.automation_filter_summary(@rule)),
        detail("Cálculo", Automations::Catalog::OPERATIONS.fetch(@rule.operation)),
        detail("Período", Automations::Period::LABELS.fetch(@rule.period)),
        detail("Condição", @rule.condition_operator == "always" ? "Sempre" : "#{AutomationRule::CONDITIONS.key(@rule.condition_operator)} #{@rule.condition_value.to_s('F')}"),
        detail("Ação", labels.automation_action_label(@rule)), detail("Execução", labels.automation_schedule_text(@rule)),
        detail("Estado ao confirmar", @rule.enabled? ? "Ativa" : "Pausada"), detail("Responsável", account_name(@user))]
      config = @rule.action_config
      if @rule.action_key == "update_indicator"
        template = RoutineTemplate.visible_to(@user).find(config.fetch("routine_template_id"))
        indicator = RoutineIndicator.find(config.fetch("routine_indicator_id"))
        details << detail("Destino", "#{template.name} / #{indicator.name}")
        details << detail("Valores manuais", config["overwrite_manual"] == "1" ? "Podem ser substituídos" : "Preservados")
      else
        details << detail("Título", config.fetch("title"))
        details << detail("Mensagem", config["body"]) if config["body"].present?
        destination = if @rule.action_key == "notify"
          "Avisos do responsável"
        elsif config["bucket_id"].present?
          bucket = Automations::Configuration.buckets_for(@user).includes(:action_plan).find(config["bucket_id"])
          "#{bucket.action_plan.name} / #{bucket.name}"
        else
          "Entrada pessoal do responsável"
        end
        details << detail("Destino", destination)
        if @rule.action_key == "create_task"
          details << detail("Prazo da tarefa", config["due_in_days"].present? ? "#{config['due_in_days']} dia(s) após executar" : "Sem prazo")
        end
      end
      @preview = { "heading" => "Criar automação", "name" => @rule.name, "description" => @rule.description,
        "confirmation_label" => @rule.enabled? ? "Salvar e ativar automação" : "Salvar automação pausada",
        "details" => details,
        "notices" => ["A confirmação salva a regra. Não preenche indicadores, cria tarefas nem envia avisos neste momento.",
          @rule.action_key == "update_indicator" ? "A regra atualiza a mesma célula do período, sem somar o valor novamente. Valores de outra automação são protegidos." : "A regra realiza no máximo uma ação por período consultado; em todo o histórico, uma única vez."] }
    end
  end
end
