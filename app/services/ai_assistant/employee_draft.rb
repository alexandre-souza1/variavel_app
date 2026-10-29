module AiAssistant
  class EmployeeDraft < ActionDraft
    IDENTITY_FIELDS = %w[nome matricula cpf data_nascimento registered_on].freeze
    ROLE_FIELDS = %w[sector cargo promax turno starts_on reason].freeze

    def self.allowed?(user)
      user&.active? && !user.mechanical? && (user.admin? || user.sector_hr?)
    end

    def initialize(user:, arguments:)
      @user, @kind = user, "create_employee"
      raise Forbidden, "Somente administradores e usuários de RH podem cadastrar colaboradores pelo assistente." unless self.class.allowed?(user)
      raise Invalid, "Dados do colaborador inválidos." unless arguments.is_a?(Hash)

      args = arguments.deep_stringify_keys
      check_keys!(args, IDENTITY_FIELDS + ROLE_FIELDS)
      @payload = {
        "nome" => text(args["nome"], "Nome completo", 255, required: true),
        "matricula" => text(args["matricula"], "Matrícula", 100, required: true),
        "cpf" => text(args["cpf"], "CPF", 32).presence,
        "data_nascimento" => date(args["data_nascimento"], "Data de nascimento"),
        "registered_on" => date(args["registered_on"], "Data de registro na carteira"),
        "sector" => text(args["sector"], "Setor", 10, required: true),
        "cargo" => text(args["cargo"], "Cargo", 30, required: true),
        "promax" => text(args["promax"], "Código Promax", 100).presence,
        "turno" => shift(args["turno"]),
        "starts_on" => date(args["starts_on"], "Início na função"),
        "reason" => text(args["reason"].presence || "Cadastro inicial pelo assistente de IA", "Motivo", 500, required: true)
      }
      raise Forbidden, "Setor de colaboradores não autorizado." unless user.employee_sectors.include?(payload["sector"])
      raise Invalid, "Turno se aplica somente ao setor AZ." if payload["sector"] == "du" && payload["turno"]
      raise Invalid, "Código Promax se aplica somente ao setor DU." if payload["sector"] == "az" && payload["promax"]

      employee = Employee.new(payload.slice(*IDENTITY_FIELDS))
      role = EmployeeRole.new(payload.slice(*ROLE_FIELDS).merge(employee: employee, pending_start: payload["starts_on"].nil?, created_by: user))
      errors = []
      errors.concat(employee.errors.full_messages) unless employee.valid?
      errors.concat(role.errors.full_messages) unless role.valid?
      raise Invalid, errors.to_sentence if errors.any?
      validate_code_owner!
      build_preview(role)
    end

    def execute!(request_id:)
      employee = Employees::Registry.create!(attributes: payload.slice(*IDENTITY_FIELDS), role: payload.slice(*ROLE_FIELDS), user: @user)
      employee.employee_career_events.create!(user: @user, details: {
        action: "create_employee", source: "ai_assistant", ai_action_request_id: request_id
      })
      { type: "employee", id: employee.id, label: "Abrir colaborador", path: routes.employee_path(employee) }
    rescue EmployeeRole::HistoryError => error
      raise Invalid, error.message
    end

    private

    def date(value, label)
      return if value.nil? || value == ""
      raise Invalid, "#{label}: use uma data YYYY-MM-DD." unless value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)
      Date.iso8601(value).iso8601
    rescue Date::Error
      raise Invalid, "#{label}: data inválida."
    end

    def shift(value)
      return if value.nil? || value == ""
      unless (value.is_a?(Integer) || value.is_a?(String)) && value.to_s.match?(/\A[012]\z/)
        raise Invalid, "Turno inválido: use A=0, B=1 ou C=2."
      end
      value.to_i
    end

    def validate_code_owner!
      return unless payload["sector"] == "du" && payload["promax"]
      cargos = payload["cargo"] == "ajudante" ? ["ajudante"] : %w[motorista van]
      roles = EmployeeRole.du.where(promax: payload["promax"], cargo: cargos)
      roles = roles.where("ends_on IS NULL OR ends_on >= ?", payload["starts_on"]) if payload["starts_on"]
      raise Invalid, "Código Promax já pertence a outro colaborador nesse período; revise os vínculos no RH." if roles.exists?
    end

    def build_preview(role)
      details = [detail("Matrícula", payload["matricula"]), detail("Setor", role.sector_label), detail("Cargo inicial", role.label),
        detail("Registro na carteira", formatted_date(payload["registered_on"])),
        detail("Início na função", formatted_date(payload["starts_on"])),
        detail(role.du? ? "Código Promax" : "Turno", role.du? ? (payload["promax"] || "A definir") : (role.shift_label || "A definir")),
        detail("Motivo", payload["reason"]), detail("Autor do cadastro", account_name(@user))]
      details << detail("CPF", payload["cpf"]) if payload["cpf"]
      details << detail("Data de nascimento", formatted_date(payload["data_nascimento"])) if payload["data_nascimento"]
      @preview = { "heading" => "Cadastrar colaborador", "name" => payload["nome"], "details" => details,
        "confirmation_label" => "Confirmar cadastro",
        "notices" => [payload["starts_on"] ? "A disponibilidade operacional segue a data de início na função." :
          "Sem início na função, o colaborador fica em integração, sem disponibilidade operacional."] }
    end

    def formatted_date(value)
      value ? I18n.l(Date.iso8601(value), format: "%d/%m/%Y") : "A definir"
    end
  end
end
