module AiAssistant
  # Resolves only permitted attributes and records. Building a preview never writes
  # business records, sends notifications or creates a personal inbox.
  class ActionDraft
    class Invalid < StandardError; end
    class Forbidden < Invalid; end
    class Stale < Invalid; end

    TASK_FIELDS = %w[title description start_at due_at user_ids reminder checklist].freeze
    attr_reader :kind, :payload, :preview

    def self.allowed?(user, kind: nil)
      user&.active? && (kind == "update_task" || !user.mechanical?)
    end

    def self.build(user:, kind:, arguments:)
      return TaskUpdateDraft.new(user: user, arguments: arguments) if kind == "update_task"

      new(user: user, kind: kind, arguments: arguments)
    end

    def self.restore(user:, kind:, payload:)
      if kind == "update_task"
        TaskUpdateDraft.new(user: user, arguments: payload.slice("task_id", "changes"), expected_state: payload.fetch("expected_state"))
      else
        new(user: user, kind: kind, arguments: payload)
      end
    end

    def initialize(user:, kind:, arguments:)
      @user = user
      @kind = kind
      raise Forbidden, "Seu perfil não permite criar tarefas ou planos pelo assistente." unless self.class.allowed?(user)
      raise Invalid, "Dados da ação inválidos." unless arguments.is_a?(Hash)

      args = arguments.deep_stringify_keys
      case kind
      when "create_task" then prepare_task(args)
      when "create_plan" then prepare_plan(args)
      else raise Invalid, "Ação indisponível."
      end
    rescue ActiveRecord::RecordNotFound
      raise Forbidden, "O plano, bucket ou responsável não está disponível para esta ação."
    rescue ArgumentError, TypeError
      raise Invalid, "Confira os dados, identificadores e datas da ação."
    end

    def to_h
      { kind: kind, payload: payload, preview: preview }
    end

    # Called exclusively by AiActionRequest after explicit confirmation.
    def execute!(request_id:)
      @request_id = request_id
      if kind == "create_plan"
        plan = @user.action_plans.create!(payload.slice("name", "description", "sector", "public"))
        bucket = plan.buckets.work.order(:position, :id).first!
        tasks = payload.fetch("tasks").each_with_index.map { |attributes, index| create_task!(bucket, attributes, position: index + 1) }
        { type: "action_plan", id: plan.id, task_ids: tasks.map(&:id),
          label: "Abrir plano de ação", path: routes.action_plan_path(plan) }
      else
        bucket = @bucket || @user.personal_inbox!
        task = create_task!(bucket, payload)
        { type: "task", id: task.id, label: "Abrir tarefa",
          path: task.inbox? ? routes.inbox_path(task_id: task.id) : routes.action_plan_path(bucket.action_plan_id, task_id: task.id) }
      end
    end

    private

    def prepare_task(args)
      check_keys!(args, TASK_FIELDS + %w[plan_id bucket_id])
      if args["plan_id"].present?
        @plan = ActionPlan.visible_to(@user).find(integer(args["plan_id"]))
        raise Invalid, "Escolha o bucket do plano antes de preparar a tarefa." if args["bucket_id"].blank?
        @bucket = @plan.buckets.work.find(integer(args["bucket_id"]))
      elsif args["bucket_id"].present?
        raise Invalid, "Informe o plano do bucket. Para sua Entrada pessoal, omita ambos."
      end
      @payload = task_attributes(args.slice(*TASK_FIELDS)).merge("plan_id" => @plan&.id, "bucket_id" => @bucket&.id)
      @preview = {
        "heading" => "Criar tarefa", "name" => payload["title"],
        "details" => [detail("Destino", @plan ? "#{@plan.name} / #{@bucket.name}" : "Sua Entrada pessoal"),
                      detail("Visibilidade", task_visibility),
                      detail("Autor da criação", account_name(@user))],
        "tasks" => [task_preview(payload)]
      }
    end

    def prepare_plan(args)
      check_keys!(args, %w[name description sector public tasks])
      sector = args["sector"].presence || @user.sector
      raise Invalid, "Selecione um setor válido para o plano." unless User.sectors.key?(sector)
      raise Forbidden, "Você só pode criar planos para seu próprio setor." unless @user.admin? || sector == @user.sector
      tasks = args.fetch("tasks", [])
      raise Invalid, "Um plano pode ter até 10 tarefas iniciais por confirmação." unless tasks.is_a?(Array) && tasks.size <= 10

      @payload = {
        "name" => text(args["name"], "Nome do plano", 200, required: true),
        "description" => text(args["description"], "Descrição", 4_000),
        "sector" => sector, "public" => boolean(args.fetch("public", false)),
        "tasks" => tasks.map { |task| task_attributes(task) }
      }
      sector_name = User::USER_SECTORS.key(sector.to_sym)
      @preview = {
        "heading" => "Criar plano de ação", "name" => payload["name"], "description" => payload["description"],
        "details" => [detail("Setor", sector_name), detail("Responsável pelo plano", account_name(@user)),
                      detail("Visibilidade", payload["public"] ? "Público para todos os usuários do app" : "Setor, dono do plano e pessoas com tarefas atribuídas"),
                      detail("Tarefas iniciais", "#{tasks.size} no bucket A Fazer")],
        "tasks" => payload["tasks"].map { |task| task_preview(task) }
      }
    end

    def task_attributes(args)
      raise Invalid, "Dados da tarefa inválidos." unless args.is_a?(Hash)
      args = args.stringify_keys
      check_keys!(args, TASK_FIELDS)
      ids = args.fetch("user_ids", [@user.id])
      raise Invalid, "Selecione até 20 responsáveis." unless ids.is_a?(Array) && ids.size <= 20
      ids = ids.map { |id| integer(id) }.uniq.sort
      raise Forbidden, "Um responsável está inativo ou não foi encontrado." unless User.active.where(id: ids).count == ids.size

      checklist = args.fetch("checklist", [])
      raise Invalid, "Use até 20 itens no checklist." unless checklist.is_a?(Array) && checklist.size <= 20
      start_at = datetime(args["start_at"], end_of_day: false)
      due_at = datetime(args["due_at"], end_of_day: true)
      raise Invalid, "O prazo deve ser igual ou posterior ao início." if start_at && due_at && start_at > due_at
      reminder = boolean(args.fetch("reminder", false))
      raise Invalid, "Informe um prazo para ativar o lembrete." if reminder && due_at.nil?

      { "title" => text(args["title"], "Título da tarefa", 200, required: true),
        "description" => text(args["description"], "Descrição", 4_000),
        "start_at" => start_at&.iso8601, "due_at" => due_at&.iso8601,
        "user_ids" => ids, "reminder" => reminder,
        "checklist" => checklist.map { |item| text(item, "Item do checklist", 500, required: true) } }
    end

    def task_preview(task)
      { "title" => task["title"], "description" => task["description"],
        "details" => [detail("Responsáveis", User.active.where(id: task["user_ids"]).order(:id).map { |user| account_name(user) }.presence&.join(", ") || "Sem responsável"),
                      detail("Início", task["start_at"] ? formatted_time(task["start_at"]) : "Ao confirmar"),
                      detail("Prazo", task["due_at"] ? formatted_time(task["due_at"]) : "Sem prazo"),
                      detail("Lembrete de vencimento", task["reminder"] ? "Ativado, conforme as notificações do app" : "Desativado")],
        "checklist" => task["checklist"] }
    end

    def create_task!(bucket, attributes, position: 1)
      task = bucket.tasks.create!(
        title: attributes.fetch("title"), description: attributes["description"], creator: @user,
        start_at: attributes["start_at"].presence || Time.current, due_at: attributes["due_at"],
        due_notification_enabled: attributes.fetch("reminder"), user_ids: attributes.fetch("user_ids"), position: position
      )
      attributes.fetch("checklist").each { |content| task.tasklist.tasklist_items.create!(content: content, completed: false) }
      TaskActivityService.log(task: task, user: @user, activity_type: :created,
        metadata: { source: "ai_assistant", ai_action_request_id: @request_id })
      task
    end

    def check_keys!(args, allowed)
      raise Invalid, "A ação contém campos não permitidos." if (args.keys - allowed).any?
    end

    def task_visibility
      return "Somente você; outros responsáveis verão a tarefa ao movê-la para um plano" unless @plan
      return "Público para todos os usuários do app" if @plan.public?

      "Setor #{User::USER_SECTORS.key(@plan.sector&.to_sym)}, dono do plano e pessoas com tarefas atribuídas"
    end

    def text(value, label, maximum, required: false)
      raise Invalid, "#{label} inválido." unless value.nil? || value.is_a?(String)
      value = value.to_s.strip
      raise Invalid, "#{label} deve ter até #{maximum} caracteres#{required ? ' e não pode ficar vazio' : ''}." if value.length > maximum || (required && value.blank?)
      value
    end

    def integer(value)
      raise ArgumentError unless value.is_a?(Integer) || value.is_a?(String)
      id = Integer(value)
      raise ArgumentError unless id.positive?
      id
    end

    def boolean(value)
      raise Invalid, "Use verdadeiro ou falso nas opções da ação." unless [true, false].include?(value)
      value
    end

    def datetime(value, end_of_day:)
      return if value.nil? || value == ""
      raise Invalid, "Use datas YYYY-MM-DD ou data e hora ISO 8601." unless value.is_a?(String)
      if value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
        date = Date.iso8601(value).in_time_zone
        end_of_day ? date.end_of_day.change(usec: 0) : date.beginning_of_day
      else
        Time.zone.iso8601(value)
      end
    end

    def formatted_time(value)
      "#{I18n.l(Time.zone.iso8601(value), format: '%d/%m/%Y às %H:%M')} (Brasília)"
    end

    def account_name(user)
      user.name.presence || "Usuário ##{user.id}"
    end

    def detail(label, value)
      { "label" => label, "value" => value }
    end

    def routes
      Rails.application.routes.url_helpers
    end
  end
end
