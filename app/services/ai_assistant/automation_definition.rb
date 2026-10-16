module AiAssistant
  # Canonical, whitelisted configuration shared by the conversational wizard and
  # confirmed draft. This never executes an automation or creates business data.
  class AutomationDefinition
    FIELDS = %w[name description source_key operation period filters condition_operator condition_value action_key action_config schedule execution_hour weekday month_day activate].freeze
    FILTERS = { "invoices" => %w[sector budget_category_id budget_category_ids], "tasks" => %w[status action_plan_id only_mine], "fleet" => %w[status] }.freeze
    ACTION_FIELDS = { "update_indicator" => %w[routine_template_id routine_indicator_id overwrite_manual], "create_task" => %w[title body bucket_id due_in_days], "notify" => %w[title body] }.freeze
    QUESTIONS = {
      "source_key" => "Quais dados você quer acompanhar: financeiro, tarefas ou disponibilidade da frota?",
      "action_key" => "O que deve acontecer: preencher um indicador do GEROT, criar uma tarefa ou enviar um aviso para você?",
      "filters" => "Quais categorias e setor financeiro deseja acompanhar? Pode escolher uma, várias ou todas as categorias permitidas.",
      "filters.status" => "Qual situação você quer acompanhar?",
      "operation" => "Você quer somar os valores, calcular a média ou contar os lançamentos?",
      "period" => "Qual período deseja consultar: hoje, ontem, semana ou mês?",
      "action_config.routine_template_id" => "Em qual modelo de GEROT devemos preencher o resultado?",
      "action_config.routine_indicator_id" => "Qual indicador desse modelo deve receber o resultado?",
      "action_config.title" => "Qual título você quer para a tarefa ou o aviso? Posso sugerir um usando o resultado.",
      "condition_value" => "Qual é o valor do limite que deve disparar a ação?",
      "schedule" => "Quando devemos verificar: manualmente, a cada hora, diariamente, semanalmente ou mensalmente?",
      "execution_hour" => "Em qual horário de Brasília devemos verificar?",
      "weekday" => "Em qual dia da semana?",
      "month_day" => "Em qual dia do mês?",
      "name" => "Como deseja chamar esta automação? Posso sugerir um nome."
    }.freeze

    attr_reader :data

    def initialize(user:, arguments:)
      @user = user
      raise ActionDraft::Forbidden, "Seu perfil não permite criar automações." unless ActionDraft.allowed?(user)
      raise ActionDraft::Invalid, "Informe uma configuração de automação." unless arguments.is_a?(Hash)
      @data = arguments.deep_stringify_keys.deep_dup
      reject_keys!(data, FIELDS)
      normalize!
      validate_partial!
    rescue Automations::Invalid => error
      raise ActionDraft::Invalid, error.message
    end

    def missing_fields
      missing = %w[source_key action_key operation period].select { |key| data[key].blank? }
      missing << "filters" if data["source_key"] == "invoices" && !data.key?("filters")
      missing << "filters.status" if data["source_key"].in?(%w[tasks fleet]) && data.dig("filters", "status").blank?
      if data["action_key"] == "update_indicator"
        %w[routine_template_id routine_indicator_id].each { |key| missing << "action_config.#{key}" if data.dig("action_config", key).blank? }
      elsif data["action_key"].in?(%w[create_task notify]) && data.dig("action_config", "title").blank?
        missing << "action_config.title"
      end
      missing << "condition_value" if data["condition_operator"] != "always" && data["condition_value"].blank?
      missing << "schedule" if data["schedule"].blank?
      missing << "execution_hour" if data["schedule"].in?(%w[daily weekly monthly]) && !data.key?("execution_hour")
      missing << "weekday" if data["schedule"] == "weekly" && !data.key?("weekday")
      missing << "month_day" if data["schedule"] == "monthly" && !data.key?("month_day")
      missing << "name" if data["name"].blank?
      missing
    end

    def rule
      raise ActionDraft::Invalid, "Faltam dados: #{missing_fields.join(', ')}. #{QUESTIONS[missing_fields.first]}" if missing_fields.any?
      result = AutomationRule.new(data.except("activate").merge("user" => @user, "enabled" => data.fetch("activate")))
      raise ActionDraft::Invalid, result.errors.full_messages.to_sentence unless result.valid?
      result
    end

    def next_question
      case missing_fields.first
      when "source_key"
        "Quais dados você quer acompanhar: #{Automations::Catalog.sources_for(@user).values.pluck(:label).join(', ')}?"
      when "filters.status"
        statuses = data["source_key"] == "fleet" ? Automations::Sources::Fleet::STATUSES : Automations::Sources::Tasks::STATUSES
        "Qual situação deseja acompanhar: #{statuses.values.join(', ')}?"
      when "period"
        data["source_key"] == "fleet" ? "Você quer acompanhar a disponibilidade de hoje ou de ontem?" : QUESTIONS["period"]
      else QUESTIONS[missing_fields.first]
      end
    end

    private

    def normalize!
      data["condition_operator"] ||= "always"
      data["activate"] = false unless data.key?("activate")
      raise ActionDraft::Invalid, "A ativação deve ser verdadeiro ou falso." unless [true, false].include?(data["activate"])
      %w[name description].each do |key|
        next unless data.key?(key)
        raise ActionDraft::Invalid, "Texto inválido na configuração." unless data[key].is_a?(String)
        data[key] = data[key].strip
        limit = key == "name" ? 120 : 2000
        raise ActionDraft::Invalid, "#{key} excede #{limit} caracteres." if data[key].length > limit
      end
      %w[execution_hour weekday month_day].each { |key| data[key] = integer(data[key], allow_zero: true) if data.key?(key) }
      if data.key?("condition_value") && data["condition_value"].present?
        raw = data["condition_value"]
        raise ActionDraft::Invalid, "Use um número decimal no limite." unless raw.is_a?(Numeric) || raw.is_a?(String)
        number = BigDecimal(raw.to_s, exception: false)
        raise ActionDraft::Invalid, "Use um número decimal válido no limite." unless number&.finite?
        data["condition_value"] = number.to_s("F")
      end
      data.delete("condition_value") if data["condition_operator"] == "always"
      %w[filters action_config].each do |key|
        next unless data.key?(key)
        raise ActionDraft::Invalid, "Configuração de filtros ou ação inválida." unless data[key].is_a?(Hash)
        data[key].delete_if { |_, value| value.nil? || value == "" }
      end
      filters = data["filters"]
      if filters && (filters.key?("budget_category_ids") || filters.key?("budget_category_id"))
        ids = Automations::Configuration.category_ids(filters)
        filters.delete("budget_category_id")
        filters["budget_category_ids"] = ids
      end
      (data["filters"] || {}).each do |key, value|
        if key == "budget_category_ids"
          next
        elsif key.end_with?("_id")
          data["filters"][key] = integer(value).to_s
        elsif key == "only_mine"
          data["filters"][key] = boolean_flag(value)
        elsif !value.is_a?(String)
          raise ActionDraft::Invalid, "Filtro inválido."
        end
      end
      (data["action_config"] || {}).each do |key, value|
        if key.end_with?("_id") || key == "due_in_days"
          data["action_config"][key] = integer(value, allow_zero: key == "due_in_days").to_s
        elsif key == "overwrite_manual"
          data["action_config"][key] = boolean_flag(value)
        elsif !value.is_a?(String)
          raise ActionDraft::Invalid, "Texto da ação inválido."
        end
      end
      data["operation"] ||= "count" if data["source_key"].in?(%w[tasks fleet])
    end

    def validate_partial!
      enums = { "source_key" => Automations::Catalog.sources_for(@user).keys,
        "action_key" => Automations::Catalog::ACTIONS.keys, "operation" => Automations::Catalog::OPERATIONS.keys,
        "period" => Automations::Period::LABELS.keys, "schedule" => AutomationRule::SCHEDULES.values,
        "condition_operator" => AutomationRule::CONDITIONS.values }
      enums.each { |key, allowed| raise(ActionDraft::Invalid, "#{key} indisponível para esta configuração ou usuário.") if data.key?(key) && !allowed.include?(data[key]) }
      { "execution_hour" => 0..23, "weekday" => 0..6, "month_day" => 1..31 }.each do |key, range|
        raise ActionDraft::Invalid, "#{key} fora do intervalo permitido." if data.key?(key) && !range.cover?(data[key])
      end
      filters = data.fetch("filters", {})
      config = data.fetch("action_config", {})
      reject_keys!(filters, data["source_key"] ? FILTERS.fetch(data["source_key"]) : FILTERS.values.flatten.uniq)
      reject_keys!(config, data["action_key"] ? ACTION_FIELDS.fetch(data["action_key"]) : ACTION_FIELDS.values.flatten.uniq)
      if data["source_key"]
        allowed_ops = Automations::Catalog::SOURCES.fetch(data["source_key"])[:operations]
        raise ActionDraft::Invalid, "Cálculo incompatível com a origem." if data["operation"] && !allowed_ops.include?(data["operation"])
      end
      if data["source_key"] == "invoices"
        categories = Automations::Configuration.categories_for(@user)
        ids = Automations::Configuration.category_ids(filters)
        raise ActionDraft::Forbidden, "Uma ou mais categorias financeiras estão indisponíveis." if ids.any? && categories.where(id: ids).count != ids.size
        if filters["sector"]
          sectors = @user.admin? || @user.sector_finance? ? BudgetCategory.sectors.keys : @user.budget_sectors
          raise ActionDraft::Forbidden, "Setor financeiro indisponível." unless sectors.include?(filters["sector"])
          if ids.any? && categories.where(sector: filters["sector"], id: ids).count != ids.size
            raise ActionDraft::Invalid, "Todas as categorias devem pertencer ao setor escolhido."
          end
        end
      elsif data["source_key"] == "tasks"
        raise ActionDraft::Invalid, "Situação de tarefa indisponível." if filters["status"] && !Automations::Sources::Tasks::STATUSES.key?(filters["status"])
        if filters["action_plan_id"] && !ActionPlan.visible_to(@user).exists?(id: filters["action_plan_id"])
          raise ActionDraft::Forbidden, "Plano de origem indisponível."
        end
      elsif data["source_key"] == "fleet"
        raise ActionDraft::Invalid, "Situação de veículo indisponível." if filters["status"] && !Automations::Sources::Fleet::STATUSES.key?(filters["status"])
        raise ActionDraft::Invalid, "Disponibilidade exige Hoje ou Ontem." if data["period"] && !data["period"].in?(%w[today yesterday])
      end
      if config["bucket_id"] && !Automations::Configuration.buckets_for(@user).exists?(id: config["bucket_id"])
        raise ActionDraft::Forbidden, "Bucket de destino indisponível."
      end
      if config["routine_template_id"] && !RoutineTemplate.visible_to(@user).exists?(id: config["routine_template_id"])
        raise ActionDraft::Forbidden, "Modelo de GEROT indisponível."
      end
      if config["routine_indicator_id"]
        indicator = RoutineIndicator.active.joins(:routine_category)
          .where(routine_categories: { routine_template_id: RoutineTemplate.visible_to(@user).select(:id) }).find_by(id: config["routine_indicator_id"])
        raise ActionDraft::Forbidden, "Indicador indisponível." unless indicator
        if config["routine_template_id"] && indicator.routine_category.routine_template_id.to_s != config["routine_template_id"]
          raise ActionDraft::Invalid, "O indicador não pertence ao modelo escolhido."
        end
        if data["period"] && Automations::Period.new(data["period"]).indicator_frequency != indicator.response_frequency
          raise ActionDraft::Invalid, "O período deve acompanhar a frequência do indicador."
        end
      end
      %w[title body].each { |key| Automations::Message.validate!(config[key], max: key == "title" ? 200 : 2000) if config[key] }
    rescue Automations::Invalid => error
      raise ActionDraft::Invalid, error.message
    end

    def reject_keys!(hash, allowed)
      raise ActionDraft::Invalid, "A configuração contém campos não permitidos." if (hash.keys - allowed).any?
    end

    def integer(value, allow_zero: false)
      unless (value.is_a?(Integer) || value.is_a?(String)) && value.to_s.match?(/\A\d+\z/) && value.to_i >= (allow_zero ? 0 : 1)
        raise ActionDraft::Invalid, "Identificador ou número inteiro inválido."
      end
      value.to_i
    end

    def boolean_flag(value)
      return "1" if value == true || value == "1"
      return "0" if value == false || value == "0"
      raise ActionDraft::Invalid, "Use verdadeiro ou falso nas opções."
    end
  end
end
