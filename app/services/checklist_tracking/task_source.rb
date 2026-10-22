module ChecklistTracking
  class TaskSource
    DATE_PATTERN = /\b(?:\d{1,2}\/\d{1,2}\/\d{4}|\d{4}-\d{2}-\d{2})\b/
    MISSING_PATTERN = /(?:nao|sem)\s+(?:realiz\w*|preench\w*|faz\w*|fez|fazer|execut\w*)[^.!?\n]*check\s*list|check\s*list[^.!?\n]*(?:nao\s+(?:realiz\w*|preench\w*|fez|feito|execut\w*)|pendente)/
    GEROT_ADHERENCE_PATTERN = /\Aaderencia (?:de )?(?:paleteira|empilhadeira|saida rota|retorno rota)\z/
    GEROT_ADHERENCE_SQL = 'ader[eêé]ncia[[:space:]]+(de[[:space:]]+)?(paleteira|empilhadeira|sa[ií]da[[:space:]]+rota|retorno[[:space:]]+rota)'
    attr_reader :task

    def initialize(task)
      @task = task
    end

    def self.candidates(tasks)
      tasks.left_joins(:comments, routine_value: :routine_indicator)
        .where("tasks.title ~* :missing OR comments.content ~* :missing OR routine_indicators.name ~* :checklist OR routine_indicators.name ~* :adherence",
          missing: '(não|nao|sem).*(check[ -]?list)|(check[ -]?list).*(não|nao|pendente)',
          checklist: 'check[ -]?list', adherence: GEROT_ADHERENCE_SQL).distinct
    end

    def suggested_date
      dates = explicit_dates.presence || parse_dates(text)
      dates.one? ? dates.first : task.routine_value&.reference_date || task.start_at&.to_date || task.created_at.to_date
    end

    def suggested_kind
      kinds.first || kinds_in(text).first || "outro"
    end

    def name_match(employees, matcher: nil)
      matcher ||= NameMatcher.new(employees)
      match = matcher.call(name: mentioned_name, text: evidence)
      return match unless match.confidence == :missing && mentioned_name.blank?
      if gerot_checklist_deviation? && gerot_name.present?
        gerot_match = matcher.call(name: gerot_name)
        return gerot_match unless gerot_match.confidence == :missing
      end
      contextual = matcher.call(text: text)
      return match unless contextual.employee
      NameMatcher::Match.new(employee: contextual.employee, confidence: :partial, reason: "Nome no contexto da ação; confira a identidade")
    end

    def suggested_employee(employees)
      name_match(employees).employee
    end

    def automatic_attributes(employees, matcher: nil)
      match = name_match(employees, matcher: matcher)
      return unless match.certain? && missing_checklist? && certain_date && kinds.one?
      { employee_id: match.employee.id, occurred_on: certain_date, checklist_kind: kinds.first }
    end

    def review_reason(employees, matcher: nil)
      match = name_match(employees, matcher: matcher)
      return match.reason unless match.certain?
      return "O texto não confirma um checklist não realizado" unless missing_checklist?
      return "A data da falta está ausente ou há várias datas" unless certain_date
      return "O tipo de checklist está ausente ou há vários tipos" unless kinds.one?
      return "Nome, tipo e data identificados na ação e na origem no GEROT" if gerot_checklist_deviation?
      "Nome, data e tipo identificados; pronto para registro automático"
    end

    def certain_date
      return if evidence.scan(DATE_PATTERN).uniq.size != explicit_dates.size
      return explicit_dates.first if explicit_dates.one?
      task.routine_value&.reference_date if explicit_dates.empty?
    end

    def missing_checklist?
      normalize(evidence).match?(MISSING_PATTERN) || gerot_checklist_deviation?
    end

    # The generated title records the original deviation even if the cell is later corrected.
    # Only completion/adherence indicators qualify; availability and fast-fill indicators do not.
    def gerot_checklist_deviation?
      indicator = task.routine_value&.routine_indicator
      return false unless indicator
      name = normalize(indicator.name)
      completion = name.match?(/\bchecklist\b/) && (indicator.boolean? || (indicator.percentage? && indicator.greater_or_equal?))
      adherence = name.match?(GEROT_ADHERENCE_PATTERN) && indicator.percentage? && indicator.greater_or_equal?
      (completion || adherence) && normalize(task.title).start_with?("investigar #{name} fora da meta ")
    end

    # The title/comment that originated the action takes precedence over later discussion.
    def evidence
      return task.routine_comment.body if task.routine_comment && normalize(task.routine_comment.body).match?(MISSING_PATTERN)
      return task.title if normalize(task.title).match?(MISSING_PATTERN)
      if gerot_checklist_deviation?
        return task.routine_comment&.body.presence || task.title
      end
      task.comments.map(&:content).find { |body| normalize(body).match?(MISSING_PATTERN) } || task.description.to_s
    end

    def text
      [task.title, task.routine_comment&.body, task.description, *task.comments.map(&:content)].compact.join("\n")
    end

    private

    def mentioned_name
      normalize(evidence)[/(?:motorista|operador(?:a)?|colaborador(?:a)?|ajudante)\s+(.+?)\s+(?:por\s+nao|nao\s+realiz)/, 1]
    end

    def gerot_name
      name = task.routine_comment&.body.presence || task.title.split(/\s+[—–]\s+/, 2).last
      name if name.present? && name.match?(/\A[\p{L}\s]+\z/)
    end

    def explicit_dates
      @explicit_dates ||= parse_dates(evidence)
    end

    def parse_dates(content)
      content.scan(DATE_PATTERN).filter_map do |date|
        date.include?("/") ? Date.strptime(date, "%d/%m/%Y") : Date.iso8601(date)
      rescue Date::Error
        nil
      end.uniq
    end

    def kinds
      @kinds ||= begin
        explicit = kinds_in(evidence)
        if gerot_checklist_deviation?
          indicator_name = task.routine_value.routine_indicator.name
          indicator_kinds = kinds_in(indicator_name)
          # Specific adherence indicators must agree with the comment. A generic
          # safety-completion indicator can still be clarified by an explicit report.
          normalize(indicator_name).match?(GEROT_ADHERENCE_PATTERN) ? (explicit + indicator_kinds).uniq : (explicit.presence || indicator_kinds)
        else
          explicit
        end
      end
    end

    def kinds_in(content)
      ChecklistOccurrence::KINDS.keys.excluding("outro").select do |kind|
        normalize(content).match?(/\b#{kind}\b/)
      end
    end

    def normalize(value)
      I18n.transliterate(value.to_s).downcase.gsub(/check[ -]+list/, "checklist").gsub(/[^a-z0-9\/\n -]/, " ").gsub(/[^\S\n]+/, " ").strip
    end
  end
end
