module ChecklistTracking
  class NameMatcher
    Match = Struct.new(:employee, :confidence, :reason, keyword_init: true) do
      def certain?
        confidence == :certain
      end
    end
    PARTICLES = %w[de da do dos das e].freeze

    def initialize(employees)
      @entries = employees.flat_map do |employee|
        ([employee.nome] + employee.employee_names.map(&:name)).uniq.map do |name|
          [employee, EmployeeName.normalize(name)]
        end
      end
    end

    def call(name: nil, text: nil, eligible_ids: nil)
      entries = eligible_ids ? @entries.select { |employee, _| eligible_ids.include?(employee.id) } : @entries
      return resolve_name(EmployeeName.normalize(name), entries) if name.present?

      normalized = EmployeeName.normalize(text)
      matches = entries.select { |_, candidate| candidate.present? && " #{normalized} ".include?(" #{candidate} ") }
      people = matches.map(&:first).uniq(&:id)
      return ambiguous if people.many?
      if people.one?
        complete = matches.any? { |_, candidate| tokens(candidate).size >= 2 }
        return Match.new(employee: people.first, confidence: complete ? :certain : :partial,
          reason: complete ? "Nome completo identificado" : "Apenas o primeiro nome foi identificado")
      end
      missing
    end

    private

    def resolve_name(name, entries)
      wanted = tokens(name)
      return missing if wanted.empty?
      matches = entries.select do |_, candidate|
        candidate_tokens = tokens(candidate)
        candidate == name || (wanted.first == candidate_tokens.first && ordered_subset?(wanted, candidate_tokens))
      end.map(&:first).uniq(&:id)
      return ambiguous if matches.many?
      if matches.one?
        return Match.new(employee: matches.first, confidence: wanted.size >= 2 && wanted.all? { |token| token.length > 1 } ? :certain : :partial,
          reason: wanted.size >= 2 ? "Nome e sobrenome identificados sem ambiguidade" : "Primeiro nome único; confira a identidade")
      end

      ranked = entries.map do |employee, candidate|
        [employee, distance(wanted.join, tokens(candidate).join), [wanted.join.length, tokens(candidate).join.length].max]
      end.group_by { |employee, _, _| employee.id }.map { |_, rows| rows.min_by { |_, score, _| score } }.sort_by { |_, score, _| score }
      first, second = ranked.first(2)
      if first && wanted.size >= 2 && first[1] <= 2 && first[1].to_f / [first[2], 1].max <= 0.15 && (!second || second[1] - first[1] >= 2)
        return Match.new(employee: first[0], confidence: :similar, reason: "Grafia semelhante; confira antes de registrar")
      end
      missing
    end

    def tokens(name)
      name.split.excluding(*PARTICLES)
    end

    def ordered_subset?(wanted, candidate)
      remaining = wanted.dup
      candidate.each { |word| remaining.shift if remaining.first == word }
      remaining.empty?
    end

    def distance(left, right)
      previous = (0..right.length).to_a
      left.each_char.with_index(1) do |char, i|
        current = [i]
        right.each_char.with_index(1) do |other, j|
          current[j] = [current[j - 1] + 1, previous[j] + 1, previous[j - 1] + (char == other ? 0 : 1)].min
        end
        previous = current
      end
      previous.last
    end

    def missing
      Match.new(confidence: :missing, reason: "Nome não encontrado no cadastro acessível")
    end

    def ambiguous
      Match.new(confidence: :ambiguous, reason: "O texto pode corresponder a mais de um colaborador")
    end
  end
end
