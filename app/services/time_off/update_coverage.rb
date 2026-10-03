module TimeOff
  class UpdateCoverage
    def self.call(schedule:, date:, attributes:, user:)
      attributes = attributes.to_h.deep_stringify_keys
      reason = attributes['reason'].to_s.strip
      raise UpdateDay::InvalidChange, 'Informe o motivo da alteração (até 500 caracteres).' if reason.length < 4 || reason.length > 500
      schedule.with_lock do
        dimensioning = FleetDimensioning.for_date(date)
        raise UpdateDay::InvalidChange, 'Não há dimensionamento vigente nesta data.' unless dimensioning
        dimensioning.with_lock do
          current = Coverage.new(schedule: schedule, date: date)
          raise UpdateDay::InvalidChange, 'Defina o dimensionamento vigente para um dia de operação da escala.' unless current.editable?
          raise UpdateDay::Conflict, 'O dimensionamento mudou. Atualize a página antes de salvar.' unless attributes['dimensioning_signature'] == current.signature
          revision = current.plan&.lock_version || -1
          raise UpdateDay::Conflict, 'A cobertura foi alterada por outra pessoa. Atualize a página.' unless attributes['expected_revision'].to_s == revision.to_s
          details = {
            'solo_routes' => integer(attributes['solo_routes']),
            'double_helper_routes' => integer(attributes['double_helper_routes']),
            'helper_driver_ids' => Array(attributes['helper_driver_ids']).reject(&:blank?).map { |id| integer(id) },
            'special_assignments' => attributes.fetch('special_assignments', {})
          }
          details['routing_import'] = attributes['routing_import'] || current.details['routing_import'] if attributes['routing_import'] || current.details['routing_import']
          if details['solo_routes'] + details['double_helper_routes'] > current.quantities['route']
            raise UpdateDay::InvalidChange, 'A soma das rotas sem ajudante e com dois ajudantes excede o dimensionamento.'
          end
          proposed = Coverage.new(schedule: schedule, date: date, details: details)
          details['cars'] = Board.validate!(proposed, attributes['cars']) if attributes.key?('cars')
          used = Set.new
          Coverage::SPECIAL_OPERATIONS.each do |operation|
            allowed_roles = operation == 'vespertina' ? %w[driver helper] : ['driver']
            submitted = details['special_assignments'].fetch(operation, {})
            raise UpdateDay::InvalidChange, 'Função inválida para a operação.' if (submitted.keys - allowed_roles).any?
            submitted.each_value do |ids|
              raise UpdateDay::InvalidChange, 'Há mais titulares que saídas dimensionadas.' if Array(ids).size > proposed.quantities[operation]
            end
            proposed.assignments[operation].each do |role, assigned|
              assigned.compact.each { |m| validate_person!(proposed, m, operation, role, used) }
              Array(submitted[role]).reject(&:blank?).each do |id|
                raise UpdateDay::InvalidChange, 'Colaborador não pertence à escala nesta data.' unless proposed.member(id)
              end
            end
          end
          raise UpdateDay::InvalidChange, 'Operação inválida.' if (details['special_assignments'].keys - Coverage::SPECIAL_OPERATIONS).any?
          details['helper_driver_ids'].each do |id|
            m = proposed.member(id)
            raise UpdateDay::InvalidChange, 'Selecione um motorista da escala para atuar como ajudante.' unless m&.role == 'driver'
            validate_person!(proposed, m, 'route', 'helper', used)
          end
          plan = current.plan || schedule.time_off_daily_plans.build(date: date)
          before = plan.details.deep_dup
          plan.update!(details: details, reason: reason, dimensioning_signature: current.signature)
          schedule.time_off_changes.create!(user: user, date: date,
            details: { action: 'coverage', before: before, after: details, reason: reason, summary: proposed.summary,
              movements: details['cars'] ? movements(proposed, attributes['previous_cars'] || before['cars'] || [], details['cars']) : [] })
          plan
        end
      end
    end

    def self.integer(value)
      number = Integer(value.to_s, 10)
      raise ArgumentError if number.negative?
      number
    rescue ArgumentError, TypeError
      raise UpdateDay::InvalidChange, 'Informe quantidades e colaboradores válidos, sem valores negativos.'
    end

    def self.validate_person!(coverage, member, operation, role, used)
      unless coverage.eligible?(member, operation: operation, role: role)
        raise UpdateDay::InvalidChange, operation == 'van' ? 'Van exige o cargo Motorista de van vigente e disponibilidade no dia.' : 'Colaborador indisponível ou com cargo incompatível. Ajuste primeiro a Escala do dia.'
      end
      raise UpdateDay::InvalidChange, 'O mesmo colaborador não pode ocupar duas posições no dia.' if used.include?(member.person_key)
      used.add(member.person_key)
    end

    def self.movements(coverage, before, after)
      previous = before.index_by { |c| [c['operation'], c['position']] }
      after.flat_map do |car|
        old = previous.fetch([car['operation'], car['position']], {})
        label = "#{Coverage::OPERATIONS[car['operation']]} #{car['position'] + 1}"
        changes = Board::ROLES.filter_map do |role|
          from, to = coverage.member(old[role]), coverage.member(car[role])
          next if from&.id == to&.id
          "#{label} · #{role == 'driver' ? 'Motorista' : "Ajudante #{role[-1]}"}: #{from&.person&.nome || 'vaga'} → #{to&.person&.nome || 'vaga'}"
        end
        changes << "#{label} · Ajudantes: #{old['helper_count']} → #{car['helper_count']}" if old['helper_count'] && old['helper_count'] != car['helper_count']
        changes << "#{label} · Placa: #{old['plate'].presence || 'sem placa'} → #{car['plate'].presence || 'sem placa'}" if old['plate'] != car['plate']
        changes << "#{label} · #{car['scheduled'] ? 'Saída prevista' : 'Sem saída no dia'}" if old.fetch('scheduled', true) != car['scheduled']
        changes
      end
    end
    private_class_method :integer, :validate_person!, :movements
  end
end
