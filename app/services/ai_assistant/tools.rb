module AiAssistant
  class Tools
    include Rails.application.routes.url_helpers
    include NavbarHelper
    include QuerySupport
    include FinanceQueries
    include PeopleQueries
    include OperationsQueries
    include ManagementQueries
    include DailyBriefing

    attr_reader :sources

    def initialize(user)
      @user = user
      @sources = []
      @access = Access.new(user)
    end

    def declarations
      core = [
        function("list_plans", "Busca os planos de ação acessíveis ao usuário pelo nome ou descrição.",
          query: string("Trecho do nome ou descrição"), page: page),
        function("summarize_plan", "Consulta descrição e totais exatos de tarefas visíveis de um plano. Use list_tasks para os detalhes das pendências.",
          plan_id: { type: "integer" }),
        function("list_tasks", "Consulta tarefas autorizadas, responsáveis e prazos. Retorna totais exatos e uma página de resultados; informe quando houver mais páginas.",
          query: string("Trecho do título ou descrição"), plan_id: { type: "integer" },
          status: { type: "string", enum: %w[open overdue completed all] },
          mine: { type: "boolean", description: "true para tarefas atribuídas ao usuário atual" },
          assignee: string("Trecho do nome de um responsável"),
          due_from: string("Data inicial inclusiva YYYY-MM-DD"), due_until: string("Data final inclusiva YYYY-MM-DD"), page: page),
        function("fleet_status", "Consulta disponibilidade da frota na data exata. Sem data, usa hoje; não substitui por outro dia.",
          date: string("YYYY-MM-DD"), plate: string("Trecho da placa"), status: { type: "string", enum: %w[all available exchange unavailable special_route] }, page: page),
        function("navigation", "Obtém links e orientações de navegação de acordo com as permissões do usuário.")
      ]
      core.reject! { |entry| entry[:name] == 'fleet_status' && !@access.allowed?(:availability) }
      core + Catalog.entries.values.filter_map { |entry| entry[:declaration] if @access.allowed?(entry[:area]) }
    end

    def call(name, arguments)
      return { error: 'Seu acesso não está ativo.' } unless @user.reload.active?
      args = arguments.is_a?(Hash) ? arguments.stringify_keys : {}
      if (entry = Catalog.entries[name])
        return { error: 'Seu perfil não possui acesso a esta consulta.' } unless @access.allowed?(entry[:area])
        args = args.slice(*entry[:declaration][:parameters][:properties].keys.map(&:to_s))
        return send(name, args)
      end
      case name
      when "list_plans" then list_plans(args)
      when "summarize_plan" then summarize_plan(args)
      when "list_tasks" then list_tasks(args)
      when "fleet_status" then fleet_status(args)
      when "navigation" then navigation
      else { error: "Função indisponível. O assistente realiza apenas consultas." }
      end
    rescue ActiveRecord::RecordNotFound
      { error: "Registro não encontrado ou sem acesso. Não presuma que ele exista." }
    rescue ArgumentError, TypeError, KeyError
      { error: "Parâmetros inválidos. Confira as datas (YYYY-MM-DD), filtros e identificadores." }
    end

    private

    def function(name, description, **properties)
      { type: "function", name: name, description: description,
        parameters: { type: "object", properties: properties } }
    end

    def string(description)
      { type: "string", description: description }
    end

    def page
      { type: "integer", description: "Página a partir de 1, com até 20 registros" }
    end

    def paginate(scope, args)
      current = Integer(args.fetch("page", 1)).clamp(1, 500)
      total = scope.except(:select, :order).count
      records = scope.offset((current - 1) * 20).limit(20).to_a
      { total: total, page: current, has_more: total > current * 20, records: records }
    end

    def search_pattern(value)
      "%#{ActiveRecord::Base.sanitize_sql_like(value.to_s.first(150))}%"
    end

    def list_plans(args)
      scope = ActionPlan.visible_to(@user)
      if args["query"].present?
        scope = scope.where("action_plans.name ILIKE :q OR action_plans.description ILIKE :q", q: search_pattern(args["query"]))
      end
      result = paginate(scope.order(:name, :id), args)
      result[:records] = result[:records].map do |plan|
        source(plan.name, action_plan_path(plan))
        { id: plan.id, name: plan.name, description: plan.description.to_s.truncate(1500) }
      end
      result
    end

    def summarize_plan(args)
      plan = ActionPlan.visible_to(@user).find(Integer(args.fetch("plan_id", 0)))
      tasks = Task.accessible_to(@user).where(buckets: { action_plan_id: plan.id })
      source(plan.name, action_plan_path(plan))
      { id: plan.id, name: plan.name, description: plan.description.to_s.truncate(3000),
        visible_tasks: tasks.count, open_tasks: tasks.where(completed: [false, nil]).count,
        completed_tasks: tasks.where(completed: true).count,
        overdue_tasks: tasks.where(completed: [false, nil]).where("due_at < ?", Time.current).count }
    end

    def list_tasks(args)
      scope = Task.accessible_to(@user)
      if args["plan_id"].present?
        plan = ActionPlan.visible_to(@user).find(Integer(args["plan_id"]))
        scope = scope.where(buckets: { action_plan_id: plan.id })
      end
      scope = scope.where(id: TaskAssignment.where(user_id: @user.id).select(:task_id)) if args["mine"] == true
      if args["assignee"].present?
        assigned = TaskAssignment.joins(:user).where("users.name ILIKE ?", search_pattern(args["assignee"]))
        scope = scope.where(id: assigned.select(:task_id))
      end
      if args["query"].present?
        scope = scope.where("tasks.title ILIKE :q OR tasks.description ILIKE :q", q: search_pattern(args["query"]))
      end
      case args.fetch("status", "open")
      when "open" then scope = scope.where(completed: [false, nil])
      when "overdue" then scope = scope.where(completed: [false, nil]).where("due_at < ?", Time.current)
      when "completed" then scope = scope.where(completed: true)
      when "all" # Mantém todas as situações.
      else raise ArgumentError
      end
      scope = scope.where("due_at >= ?", Date.iso8601(args["due_from"]).in_time_zone.beginning_of_day) if args["due_from"].present?
      scope = scope.where("due_at <= ?", Date.iso8601(args["due_until"]).in_time_zone.end_of_day) if args["due_until"].present?
      result = paginate(scope.includes(:users, bucket: :action_plan).order(Arel.sql("tasks.due_at ASC NULLS LAST, tasks.id ASC")), args)
      result[:records] = result[:records].map do |task|
        path = if task.inbox?
                 inbox_path
               elsif @user.mechanical?
                 mechanic_tasks_path(status: task.completed? ? "completed" : "open", q: task.title, anchor: "task_#{task.id}")
               else
                 action_plan_path(task.bucket.action_plan_id, task_id: task.id)
               end
        source(task.title, path)
        { id: task.id, title: task.title, description: task.description.to_s.truncate(1000),
          completed: task.completed?, due_at: task.due_at&.iso8601,
          assignees: task.users.map(&:name), bucket: task.bucket.name, plan: task.bucket.action_plan&.name }
      end
      result
    end

    def fleet_status(args)
      return { error: "Seu perfil não tem acesso à consulta de frota." } unless can_view_nav_link?(:availability, @user)

      date = args["date"].present? ? Date.iso8601(args["date"]) : Date.current
      fleet = FleetAvailability.find_by(date: date)
      return { date: date.iso8601, available: false, message: "Não há disponibilidade cadastrada nesta data." } unless fleet

      items = fleet.fleet_availability_items.includes(:plate).select { |item| item.plate.active_on?(date) }
      counts = items.group_by(&:status).transform_values(&:size)
      status = args.fetch("status", "all")
      raise ArgumentError unless status == "all" || FleetAvailabilityItem.statuses.key?(status)

      filtered = status == "all" ? items : items.select { |item| item.status == status }
      filtered = filtered.select { |item| item.plate.placa.to_s.downcase.include?(args['plate'].to_s.downcase) } if args['plate'].present?
      current = Integer(args.fetch("page", 1)).clamp(1, 500)
      source("Disponibilidade de #{I18n.l(date)}", fleet_availability_path(fleet))
      { date: date.iso8601, available: true, updated_at: fleet.updated_at.iso8601,
        agreed_quantity: fleet.agreed_quantity, counts: counts, total: filtered.size,
        page: current, has_more: filtered.size > current * 20,
        records: filtered.slice((current - 1) * 20, 20).to_a.map do |item|
          { plate: item.plate.placa, status: item.status_label, reason: item.unavailable? ? item.reason_label : nil,
            observation: item.observation.to_s.truncate(1000) }
        end }
    end

    def navigation
      links = [{ label: "Minhas tarefas e planos de ação", path: @user.mechanical? ? mechanic_tasks_path : action_plans_path,
                 help: "Abra um plano para consultar tarefas, responsáveis, prazos e pendências." }]
      if can_view_nav_link?(:availability, @user)
        links << { label: "Disponibilidade de frota", path: fleet_availabilities_path, help: "Selecione a data para consultar os veículos." }
      end
      if @user.admin?
        links << { label: "Usuários e permissões", path: admin_users_index_path, help: "Abra o usuário, altere o perfil ou setor e salve." }
        links << { label: "Configurações de IA", path: edit_admin_ai_setting_path, help: "Escolha o modelo de IA usado pelo app." }
      end
      links.each { |link| source(link[:label], link[:path]) }
      module_links = {
        finance: ['Financeiro', invoices_path], employees: ['Colaboradores', employees_path],
        du: ['Dashboard DU', dashboard_mapas_path], az: ['Dashboard Armazém', dashboard_az_path],
        time_off: ['Escala de folgas', time_off_schedule_path], consumption: ['Consumo de combustível', fuel_consumptions_path],
        pcd: ['PCD SALAS', pcd_path], routines: ['GEROT', routines_path],
        plates: ['Placas', plates_path], tires: ['Pneus', tire_inspections_path],
        stress: ['Stress Test', stress_tests_path], documents: ['Documentos e padrões', downloads_path],
        public_resources: ['Rotogramas', rotogramas_path], checklists: ['Histórico de checklists', historic_checklists_path]
      }
      module_links.each do |area, (label, path)|
        next unless @access.allowed?(area)
        links << { label: label, path: path, help: 'Consulte os dados disponíveis neste módulo.' }
        source(label, path)
      end
      { links: links, capabilities: declarations.map { |entry| { name: entry[:name], description: entry[:description] } },
        note: 'As consultas respeitam o perfil, setor e acesso aos registros. Alterações devem ser feitas nas telas do app. Conversas pessoais permanecem privadas.' }
    end

    def source(label, path)
      @sources << { label: label.to_s.truncate(100), path: path }
      @sources.uniq! { |item| item[:path] }
    end
  end
end
