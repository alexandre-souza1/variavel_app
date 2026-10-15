module AiAssistant
  module ActionTools
    ACTION_FUNCTIONS = %w[action_options pending_actions prepare_task prepare_plan prepare_task_update].freeze

    def action_declarations
      return [] unless ActionDraft.allowed?(@user, kind: "update_task")

      task_fields = {
        title: string("Título da tarefa, até 200 caracteres"), description: string("Descrição, até 4000 caracteres"),
        start_at: string("Início YYYY-MM-DD ou ISO 8601 com hora; omitido significa ao confirmar"),
        due_at: string("Prazo YYYY-MM-DD (até 23:59:59 de Brasília) ou ISO 8601 com hora"),
        user_ids: { type: "array", items: { type: "integer" }, description: "IDs de contas ativas localizadas em action_options; omitido atribui ao usuário atual; [] deixa sem responsável" },
        reminder: { type: "boolean", description: "Ativar lembretes do app para o prazo; requer due_at" },
        checklist: { type: "array", items: { type: "string" }, description: "Até 20 itens do checklist" }
      }
      declarations = [
        function("pending_actions", "Consulta as propostas pendentes da conversa atual para ajustar os dados ou orientar a confirmação. Não executa ações nem retorna tokens de confirmação."),
        function("action_options", "Consulta opções autorizadas para criar tarefas e planos: buckets de um plano, contas ativas para atribuição e setores permitidos. Localize o plano com list_plans. Não cria registros.",
          plan_id: { type: "integer" }, assignee_query: string("Trecho do nome da conta responsável; use para resolver nomes antes da proposta"), page: page),
        function("prepare_task_update", "Prepara alterações em UMA tarefa acessível, com comparação antes/depois e confirmação por botão. Localize com list_tasks/task_details. Informe somente os campos solicitados; não executa a alteração. Não move nem exclui tarefas.",
          task_id: { type: "integer" }, changes: { type: "object", properties: task_fields.except(:checklist).merge(
            start_at: string("Novo início YYYY-MM-DD ou ISO 8601; omitido preserva o início atual"),
            due_at: { type: "string", description: "Prazo YYYY-MM-DD ou ISO 8601; string vazia remove o prazo e desativa o lembrete" },
            user_ids: { type: "array", items: { type: "integer" }, description: "Lista completa dos responsáveis desejados; omitida preserva os atuais. Para adicionar/remover, consulte task_details e preserve os demais IDs; [] remove todos" },
            completed: { type: "boolean", description: "true conclui, false reabre a tarefa" }
          ) }),
        function("prepare_task", "Prepara a prévia de UMA tarefa para confirmação por botão. NÃO cria nem executa a tarefa. Sem plano/bucket, usa a Entrada pessoal; para plano, informe ambos os IDs consultados em action_options.",
          **task_fields, plan_id: { type: "integer" }, bucket_id: { type: "integer" }),
        function("prepare_plan", "Prepara a prévia de um plano e até 10 tarefas iniciais no bucket A Fazer. NÃO cria registros. A criação depende da confirmação por botão. Por padrão, plano do setor do usuário, não público; só admin escolhe outro setor.",
          name: string("Nome do plano, até 200 caracteres"), description: string("Descrição, até 4000 caracteres"),
          sector: { type: "string", enum: User.sectors.keys }, public: { type: "boolean", description: "true torna o plano público para todos os usuários do app; use somente se solicitado" },
          tasks: { type: "array", items: { type: "object", properties: task_fields, required: ["title"] } })
      ]
      declarations.reject! { |entry| %w[prepare_task prepare_plan].include?(entry[:name]) } unless ActionDraft.allowed?(@user)
      declarations
    end

    def call_action(name, args)
      return { error: "Seu perfil não permite usar ações do assistente." } unless ActionDraft.allowed?(@user, kind: "update_task")
      return action_options(args) if name == "action_options"
      return pending_actions if name == "pending_actions"

      kind = { "prepare_task" => "create_task", "prepare_plan" => "create_plan", "prepare_task_update" => "update_task" }.fetch(name)
      draft = ActionDraft.build(user: @user, kind: kind, arguments: args)
      # Repeated tool calls in the same response must not duplicate a proposal.
      unless @drafts.any? { |existing| existing[:kind] == draft.kind && existing[:payload] == draft.payload }
        return { error: "Prepare até 3 propostas por resposta. Agrupe tarefas iniciais em um plano." } if @drafts.size >= 3
        @drafts << draft.to_h
      end
      { confirmation_required: true, executed: false, preview: draft.preview,
        note: "Somente a prévia foi preparada. O app exibirá os botões de confirmar, ajustar e cancelar. Nenhum registro foi criado ou alterado. Uma mensagem de texto não confirma a ação." }
    rescue ActionDraft::Invalid => error
      { error: error.message }
    end

    def action_options(args)
      buckets = []
      if args["plan_id"].present?
        plan = ActionPlan.visible_to(@user).find(Integer(args["plan_id"]))
        buckets = plan.buckets.work.order(:position, :id).map { |bucket| { id: bucket.id, name: bucket.name, plan_id: plan.id, plan: plan.name } }
      end
      accounts = User.active.order(:name, :id)
      accounts = accounts.where("users.name ILIKE ?", search_pattern(args["assignee_query"])) if args["assignee_query"].present?
      accounts = paginate(accounts, args)
      accounts[:records] = accounts[:records].map { |user| { id: user.id, name: user.name.presence || "Usuário ##{user.id}" } }
      { current_user_id: @user.id, personal_inbox: "Sua Entrada pessoal, privada; omita plan_id e bucket_id",
        plan_buckets: buckets, assignees: accounts,
        can_create: ActionDraft.allowed?(@user), can_update_tasks: true,
        allowed_plan_sectors: ActionDraft.allowed?(@user) ? (@user.admin? ? User.sectors.keys : [@user.sector]) : [] }
    end

    def pending_actions
      requests = AiActionRequest.pending.joins(:ai_conversation)
        .where(user: @user, ai_conversations: { user_id: @user.id }).where("expires_at > ?", Time.current)
        .order(id: :desc).limit(3)
      proposals = requests.filter_map do |request|
        draft = ActionDraft.restore(user: @user, kind: request.kind, payload: request.payload)
        { kind: draft.kind, data: draft.payload.except("expected_state"), preview: draft.preview }
      rescue ActionDraft::Invalid
        nil
      end
      { proposals: proposals, note: "Somente o botão de confirmação da prévia pode executar. Para ajustar, prepare uma nova proposta com os dados desejados." }
    end
  end
end
