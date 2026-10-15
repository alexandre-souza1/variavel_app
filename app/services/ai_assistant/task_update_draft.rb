module AiAssistant
  class TaskUpdateDraft < ActionDraft
    FIELDS = %w[title description start_at due_at user_ids reminder completed].freeze
    PREVIEW_FIELDS = %w[completed due_at user_ids start_at reminder title description].freeze
    LABELS = { "title" => "Título", "description" => "Descrição", "start_at" => "Início", "due_at" => "Prazo",
               "user_ids" => "Responsáveis", "reminder" => "Lembrete de vencimento", "completed" => "Situação" }.freeze

    def initialize(user:, arguments:, expected_state: nil)
      @user = user
      @kind = "update_task"
      raise Forbidden, "Seu perfil não permite atualizar tarefas." unless ActionDraft.allowed?(user, kind: kind)
      raise Invalid, "Dados da alteração inválidos." unless arguments.is_a?(Hash)

      args = arguments.deep_stringify_keys
      check_keys!(args, %w[task_id changes])
      @task = Task.accessible_to(user).includes(:users, bucket: :action_plan).find(integer(args.fetch("task_id")))
      @bucket = @task.bucket
      @plan = @bucket.action_plan
      state = current_state
      if expected_state && expected_state != state
        raise Stale, "A tarefa mudou desde a prévia. Consulte os dados atuais e peça uma nova proposta."
      end

      changes = normalize_changes(args["changes"])
      @payload = { "task_id" => @task.id, "changes" => changes, "expected_state" => state }
      @preview = {
        "heading" => changes == { "completed" => true } ? "Concluir tarefa" : "Atualizar tarefa",
        "name" => @task.title, "confirmation_label" => "Confirmar alterações",
        "details" => [detail("Destino", @plan ? "#{@plan.name} / #{@bucket.name}" : "Sua Entrada pessoal"),
                      detail("Visibilidade", task_visibility), detail("Autor da alteração", account_name(@user))],
        "changes" => PREVIEW_FIELDS.filter_map do |field|
          { "label" => LABELS.fetch(field), "before" => display(field, current_value(field)), "after" => display(field, changes[field]) } if changes.key?(field)
        end,
        "notices" => completion_notices(changes)
      }
    rescue ActiveRecord::RecordNotFound
      raise Forbidden, "Tarefa não encontrada ou sem acesso para alteração."
    rescue ArgumentError, TypeError, KeyError
      raise Invalid, "Confira a tarefa, as datas e os dados da alteração."
    end

    def execute!(request_id:)
      changes = payload.fetch("changes")
      attributes = changes.except("reminder")
      attributes["due_notification_enabled"] = changes["reminder"] if changes.key?("reminder")
      attributes["completed_at"] = changes["completed"] ? Time.current : nil if changes.key?("completed")
      previous_assignees = @task.users.to_a
      @task.update!(attributes)
      metadata = { source: "ai_assistant", ai_action_request_id: request_id }
      changes.each do |field, value|
        if field == "user_ids"
          log_assignees(previous_assignees, value, metadata)
        else
          activity_type = case field
                          when "completed" then value ? :completed : :reopened
                          when "due_at" then :due_date_changed
                          when "start_at" then :start_date_changed
                          when "description" then :description_changed
                          else :updated
                          end
          TaskActivityService.log(task: @task, user: @user, activity_type: activity_type,
            old_value: payload["expected_state"][field], new_value: value, metadata: metadata.merge(field: field))
        end
      end
      { type: "task", id: @task.id, title: @task.title, label: "Abrir tarefa", completed: @task.completed?, path: task_path }
    end

    private

    def current_state
      FIELDS.to_h { |field| [field, current_value(field)] }.merge(
        "version" => @task.updated_at.iso8601(6), "bucket_id" => @task.bucket_id,
        "creator_id" => @task.creator_id, "recurrence" => @task.recurrence,
        "clone_tasklist_on_recurrence" => @task.clone_tasklist_on_recurrence?,
        "completed_at" => @task.completed_at&.iso8601(6)
      )
    end

    def current_value(field)
      case field
      when "user_ids" then @task.users.map(&:id).uniq.sort
      when "reminder" then @task.due_notification_enabled?
      when "completed" then @task.completed?
      when "start_at", "due_at" then @task.attribute_in_database(field)&.in_time_zone&.iso8601(6)
      else @task.public_send(field).to_s
      end
    end

    def normalize_changes(args)
      raise Invalid, "Informe o que deseja alterar na tarefa." unless args.is_a?(Hash) && args.any?
      check_keys!(args, FIELDS)
      changes = args.to_h do |field, value|
        parsed = case field
                 when "title" then text(value, "Título", 200, required: true)
                 when "description" then text(value, "Descrição", 4_000)
                 when "start_at"
                   raise Invalid, "Informe uma data de início válida." if value.blank?
                   datetime(value, end_of_day: false).iso8601(6)
                 when "due_at" then datetime(value, end_of_day: true)&.iso8601(6)
                 when "completed", "reminder" then boolean(value)
                 when "user_ids" then assignee_ids(value)
                 end
        [field, parsed]
      end
      changes["reminder"] = false if changes.key?("due_at") && changes["due_at"].nil? && !changes.key?("reminder")
      start_at = changes.fetch("start_at", current_value("start_at"))
      due_at = changes.fetch("due_at", current_value("due_at"))
      if changes.keys.intersect?(%w[start_at due_at]) && start_at && due_at && Time.iso8601(start_at) > Time.iso8601(due_at)
        raise Invalid, "O prazo deve ser igual ou posterior ao início."
      end
      if changes.fetch("reminder", current_value("reminder")) && due_at.nil?
        raise Invalid, "Informe um prazo para ativar o lembrete."
      end
      changes.reject! { |field, value| current_value(field) == value }
      raise Invalid, "A tarefa já está com esses dados. Nenhuma alteração é necessária." if changes.empty?
      FIELDS.filter_map { |field| [field, changes[field]] if changes.key?(field) }.to_h
    end

    def assignee_ids(value)
      raise Invalid, "Selecione até 20 responsáveis." unless value.is_a?(Array) && value.size <= 20
      ids = value.map { |id| integer(id) }.uniq.sort
      raise Forbidden, "Um responsável está inativo ou não foi encontrado." unless User.active.where(id: ids).count == ids.size
      ids
    end

    def display(field, value)
      case field
      when "completed" then value ? "Concluída" : "Aberta"
      when "reminder" then value ? "Ativado" : "Desativado"
      when "start_at", "due_at" then value ? formatted_time(value) : "Não definido"
      when "user_ids"
        User.where(id: value).order(:id).map { |user| account_name(user) }.presence&.join(", ") || "Sem responsável"
      else value.presence || "Não preenchido"
      end
    end

    def completion_notices(changes)
      return [] unless changes["completed"] && @task.recurrence.present? && changes.fetch("due_at", current_value("due_at"))

      ["A recorrência será mantida. Ao concluir, o fluxo normal do app poderá gerar a próxima ocorrência da tarefa."]
    end

    def log_assignees(previous, ids, metadata)
      previous.reject { |user| ids.include?(user.id) }.each do |user|
        TaskActivityService.log(task: @task, user: @user, activity_type: :assignee_removed,
          old_value: account_name(user), metadata: metadata.merge(user_id: user.id))
      end
      User.where(id: ids - previous.map(&:id)).find_each do |user|
        TaskActivityService.log(task: @task, user: @user, activity_type: :assignee_added,
          new_value: account_name(user), metadata: metadata.merge(user_id: user.id))
      end
    end

    def task_path
      return routes.inbox_path(task_id: @task.id) if @task.inbox?
      return routes.mechanic_tasks_path(status: @task.completed? ? "completed" : "open", q: @task.title, anchor: "task_#{@task.id}") if @user.mechanical?

      routes.action_plan_path(@plan.id, task_id: @task.id)
    end
  end
end
