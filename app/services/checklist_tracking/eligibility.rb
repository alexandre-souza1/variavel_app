module ChecklistTracking
  class Eligibility
    attr_reader :role

    def initialize(employee:, date:)
      @role = employee&.role_on(date)
    end

    def allowed_kinds
      return unless role
      case [role.sector, role.cargo]
      when %w[az ajudante] then %w[paleteira]
      when %w[az operador] then %w[empilhadeira]
      when %w[du motorista] then %w[saida retorno]
      when %w[du ajudante] then []
      end
    end

    def allows?(kind)
      allowed_kinds.nil? || allowed_kinds.include?(kind)
    end

    def reason(kind)
      return if allows?(kind)
      return "Ajudante DU não realiza checklist e não entra na contagem de faltas." if role.du? && role.cargo == "ajudante"
      "#{role.label} #{role.sector.upcase} só pode receber faltas de checklist de #{allowed_kinds.map { |value| ChecklistOccurrence::KINDS.fetch(value).downcase }.join(' ou ')}."
    end
  end
end
