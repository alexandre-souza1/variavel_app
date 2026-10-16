module AiAssistant
  module AutomationTools
    FUNCTIONS = %w[automation_options configure_automation prepare_automation].freeze

    def automation_declarations
      return [] unless ActionDraft.allowed?(@user)
      properties = automation_properties
      [function("automation_options", "Consulta o catálogo real e as opções autorizadas para montar automações: origens, cálculos, períodos, condições, ações, categorias, modelos/indicadores de GEROT, planos e buckets. Não adivinhe IDs. Buscas são paginadas.",
        group: { type: "string", enum: %w[catalog categories templates indicators plans buckets] }, query: string("Trecho do nome"),
        template_id: { type: "integer" }, plan_id: { type: "integer" }, page: page),
       function("configure_automation", "Guarda ou consulta as escolhas parciais da montagem nesta conversa. Não salva uma automação. Envie só os campos respondidos; retorna configuração acumulada, campos que faltam e próxima pergunta. reset=true inicia outra montagem. Pergunte um passo por vez; quando ready=true, use prepare_automation.",
        configuration: { type: "object", properties: properties }, reset: { type: "boolean" }),
       function("prepare_automation", "Prepara a regra completa para confirmação por botão. Sem configuration, usa a montagem guardada nesta conversa. Valida permissões e retorna prévia e simulação de leitura; NÃO salva, ativa nem executa uma automação. activate=true exige escolha explícita do usuário e será destacado no botão de confirmação.",
        configuration: { type: "object", properties: properties })]
    end

    def automation_setup_context
      automation_wizard.read
    rescue ActionDraft::Invalid
      { unavailable: true, note: "A montagem anterior perdeu validade. Consulte as opções atuais e recomece com reset=true; não reutilize dados antigos." }
    end

    private

    def automation_properties
      {
        name: string("Nome descritivo, até 120 caracteres; pode sugerir conforme o objetivo"), description: string("Descrição opcional, até 2000 caracteres"),
        source_key: { type: "string", enum: Automations::Catalog.sources_for(@user).keys },
        operation: { type: "string", enum: Automations::Catalog::OPERATIONS.keys },
        period: { type: "string", enum: Automations::Period::LABELS.keys },
        filters: { type: "object", properties: {
          budget_category_ids: { type: "array", items: { type: "integer" }, description: "Lista completa das categorias financeiras selecionadas; use uma ou várias. Substitui a seleção anterior. [] significa todas as categorias permitidas, somente se escolhido explicitamente" },
          sector: string("Setor financeiro autorizado; consulte automation_options"),
          status: string("tasks: pending, overdue ou completed; fleet: unavailable, available, exchange ou special_route"),
          action_plan_id: { type: "integer" }, only_mine: { type: "boolean" }
        }, description: "Use só filtros da origem escolhida; invoices: budget_category_ids/sector; tasks: status/plan/only_mine; fleet: status. {} no financeiro significa todas as categorias permitidas, somente se escolhido." },
        condition_operator: { type: "string", enum: AutomationRule::CONDITIONS.values, description: "Omitido usa always; sem limite pedido não invente um" },
        condition_value: { type: "number", description: "Limite numérico da condição; obrigatória salvo always" },
        action_key: { type: "string", enum: Automations::Catalog::ACTIONS.keys },
        action_config: { type: "object", properties: {
          routine_template_id: { type: "integer" }, routine_indicator_id: { type: "integer" },
          overwrite_manual: { type: "boolean", description: "Por padrão falso; true somente quando explicitamente solicitado" },
          title: string("Título da tarefa ou aviso; até 200 caracteres; permite {{valor}}, {{periodo}}, {{automacao}}"),
          body: string("Descrição da tarefa ou aviso, até 2000 caracteres"), bucket_id: { type: "integer" },
          due_in_days: { type: "integer", description: "Prazo da tarefa entre 0 e 365 dias após execução; omitido não tem prazo" }
        }, description: "Só os campos da ação: update_indicator usa modelo/indicador/overwrite; create_task usa title/body/bucket/due; notify usa title/body" },
        schedule: { type: "string", enum: AutomationRule::SCHEDULES.values },
        execution_hour: { type: "integer", description: "Hora inteira de 0 a 23 em Brasília; obrigatória para daily/weekly/monthly" },
        weekday: { type: "integer", description: "Dia semanal, domingo=0 até sábado=6; obrigatório em weekly" },
        month_day: { type: "integer", description: "Dia mensal de 1 a 31; obrigatório em monthly" },
        activate: { type: "boolean", description: "Padrão false salva pausada. true só se o usuário escolher deixar ativa; nunca executa imediatamente" }
      }
    end

    def call_automation(name, args)
      raise ActionDraft::Forbidden, "Seu perfil não permite montar automações." unless ActionDraft.allowed?(@user)
      return automation_options(args) if name == "automation_options"
      if name == "configure_automation"
        reset = args.fetch("reset", false)
        raise ActionDraft::Invalid, "Reset deve ser verdadeiro ou falso." unless [true, false].include?(reset)
        patch = args.fetch("configuration", {})
        raise ActionDraft::Invalid, "Configuração inválida." unless patch.is_a?(Hash)
        return automation_wizard.change(patch.deep_stringify_keys, reset: reset)
      end
      arguments = args["configuration"] || automation_wizard.read.fetch(:configuration, {})
      draft = AutomationDraft.new(user: @user, arguments: arguments)
      unless @drafts.any? { |existing| existing[:kind] == draft.kind && existing[:payload] == draft.payload }
        return { error: "Prepare até 3 propostas por resposta." } if @drafts.size >= 3
        @drafts << draft.to_h
      end
      { confirmation_required: true, executed: false, preview: draft.preview, simulation: draft.simulation,
        note: "O app exibirá a confirmação da automação. Texto, sim ou pode fazer não confirmam. A confirmação salva a regra no estado mostrado e não executa sua ação agora." }
    rescue ActionDraft::Invalid => error
      { error: error.message }
    end

    def automation_wizard
      AutomationWizard.new(user: @user, conversation: @conversation, request_token: @request_token)
    end

    def automation_options(args)
      source("Central de automações", automation_rules_path)
      group = args.fetch("group", "catalog")
      if group == "catalog"
        return { sources: Automations::Catalog.sources_for(@user).map { |key, entry| { key: key, label: entry[:label], operations: entry[:operations] } },
          actions: Automations::Catalog::ACTIONS.map { |key, entry| { key: key, label: entry[:label] } },
          operations: Automations::Catalog::OPERATIONS, periods: Automations::Period::LABELS,
          conditions: AutomationRule::CONDITIONS, schedules: AutomationRule::SCHEDULES,
          sectors: @access.allowed?(:finance) ? (@user.admin? || @user.sector_finance? ? BudgetCategory.sectors.keys : @user.budget_sectors) : [],
          task_statuses: Automations::Sources::Tasks::STATUSES, fleet_statuses: Automations::Sources::Fleet::STATUSES,
          defaults: { activate: false, overwrite_manual: false, task_destination: "Entrada pessoal do responsável" },
          rules: ["Dados financeiros por emissão; não comprovam pagamento", "GEROT exige frequência do indicador igual ao período, exceto mês até ontem que preenche indicador diário", "Sem GEROT aberto ou disponibilidade na data, a execução registra o motivo e não escreve",
            "Hora inteira em Brasília; dias 29–31 ajustados ao fim do mês", "Tarefas/avisos no máximo uma vez por período; todo o histórico uma única vez", "A confirmação salva a regra, sem executar a ação naquele momento"] }
      end
      scope, name_field = case group
      when "categories"
        raise ActionDraft::Forbidden, "Seu perfil não possui acesso ao financeiro." unless @access.allowed?(:finance)
        [Automations::Configuration.categories_for(@user), "budget_categories.name"]
      when "templates" then [RoutineTemplate.visible_to(@user), "routine_templates.name"]
      when "indicators"
        template = RoutineTemplate.visible_to(@user).find(Integer(args.fetch("template_id")))
        [RoutineIndicator.active.joins(:routine_category).where(routine_categories: { routine_template_id: template.id }).where(value_type: %i[integer decimal currency]), "routine_indicators.name"]
      when "plans" then [ActionPlan.visible_to(@user), "action_plans.name"]
      when "buckets"
        plan = ActionPlan.visible_to(@user).find(Integer(args.fetch("plan_id")))
        [plan.buckets.work, "buckets.name"]
      else raise ActionDraft::Invalid, "Grupo de opções indisponível."
      end
      scope = scope.where("#{name_field} ILIKE ?", search_pattern(args["query"])) if args["query"].present?
      result = paginate(scope.reorder(name_field, :id), args)
      result[:records] = result[:records].map do |record|
        values = { id: record.id, name: record.name }
        case group
        when "categories" then values.merge(sector: record.sector)
        when "templates" then values.merge(sector: record.sector, plan_id: record.action_plan_id)
        when "indicators" then values.merge(template_id: template.id, value_type: record.value_type, frequency: record.response_frequency)
        else values
        end
      end
      result.merge(group: group)
    end
  end
end
