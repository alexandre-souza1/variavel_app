module Pcd
  class Save
    EDITABLE = %w[plate scheduled operation helper_count driver helper1 helper2 room departure_time external_driver external_helper1 external_helper2 notes].freeze

    def self.call(date:, attributes:, user:)
      attributes = attributes.to_h.deep_stringify_keys
      reason = attributes['reason'].to_s.strip
      raise TimeOff::UpdateDay::InvalidChange, 'Informe um motivo entre 4 e 500 caracteres.' unless (4..500).cover?(reason.length)
      PcdPlan.transaction do
        # Also serialize first saves, before there is a plan row to lock.
        PcdPlan.connection.execute("SELECT pg_advisory_xact_lock(#{date.jd})")
        schedule = TimeOffSchedule.order(:id).first
        if schedule
          schedule.with_lock { persist(date, attributes, reason, user) }
        else
          persist(date, attributes, reason, user)
        end
      end
    end

    def self.persist(date, attributes, reason, user)
      plan = PcdPlan.find_by(date: date)
      revision = plan&.lock_version || -1
      raise TimeOff::UpdateDay::Conflict, 'O PCD foi alterado por outra pessoa. Atualize a página.' unless attributes['expected_revision'].to_s == revision.to_s
      board = Board.new(date: date, plan: plan)
      source = RoutingCsv.verify(attributes['routing_token'], date: date) if attributes['routing_token'].present?
      baseline = source ? RoutingCsv.merge(board, source) : board.cars
      cars = validate!(board, baseline, attributes['cars'], source)
      before = plan&.details&.deep_dup || { 'cars' => board.cars }
      details = (plan&.details || {}).deep_dup.merge('cars' => cars)
      details['routing_import'] = source if source
      plan ||= PcdPlan.new(date: date)
      plan.update!(details: details)
      if source
        plan.pcd_imports.create!(user: user, filename: source['filename'], digest: source['digest'],
          details: source.merge('routes' => source['rows'].size, 'maps' => source['rows'].sum { |r| r['maps'].size },
            'own' => source['rows'].count { |r| !r['freight'] }, 'freight' => source['rows'].count { |r| r['freight'] }, 'saved_cars' => cars))
      end
      plan.pcd_changes.create!(user: user, action: source ? 'import' : 'update', reason: reason,
        details: { before: before, after: details, movements: movements(board, before.fetch('cars', []), cars) })
      plan
    end

    def self.validate!(board, baseline, submitted, source)
      raise TimeOff::UpdateDay::InvalidChange, 'Envie todas as rotas do painel.' unless submitted.is_a?(Array) && submitted.all? { |c| c.is_a?(Hash) }
      by_key = baseline.index_by { |car| car['key'] }
      keys = submitted.map { |car| car['key'] }
      raise TimeOff::UpdateDay::InvalidChange, 'As rotas mudaram. Recarregue o painel.' unless keys.uniq.size == keys.size && keys.sort == by_key.keys.sort
      imported = Array(source&.fetch('rows', nil)).map { |row| row['plate'] } + board.cars.filter_map { |car| car['imported_plate'] } + board.cars.filter_map { |car| car['plate'] }
      known = Plate.all.index_by { |plate| TimeOff::RoutingCsv.plate(plate.placa) }
      people = Set.new
      plates = Set.new
      submitted.map do |raw|
        car = by_key.fetch(raw['key']).deep_dup.merge(raw.slice(*EDITABLE))
        car['scheduled'] = ActiveModel::Type::Boolean.new.cast(car['scheduled']) == true
        car['plate'] = TimeOff::RoutingCsv.plate(car['plate']).presence
        car['helper_count'] = Integer(car['helper_count'].to_s, 10)
        raise TimeOff::UpdateDay::InvalidChange, 'Operação inválida.' unless TimeOff::Coverage::OPERATIONS.key?(car['operation'])
        raise TimeOff::UpdateDay::InvalidChange, 'Escolha zero, um ou dois ajudantes.' unless (0..2).cover?(car['helper_count'])
        raise TimeOff::UpdateDay::InvalidChange, 'Sala ou horário inválido.' unless Board::ROOMS.key?(car['room']) && car['departure_time'].to_s.match?(/\A(?:[01]\d|2[0-3]):[0-5]\d\z/)
        %w[external_driver external_helper1 external_helper2 notes].each { |field| raise TimeOff::UpdateDay::InvalidChange, 'Nome externo ou observação muito longo.' if car[field].to_s.length > (field == 'notes' ? 500 : 150) }
        %w[external_driver external_helper1 external_helper2].each do |field|
          raise TimeOff::UpdateDay::InvalidChange, 'Nomes externos são exclusivos das rotas de freteiros.' if !car['freight'] && car[field].present?
        end
        if car['plate']
          registered = known[car['plate']]
          allowed = registered ? registered.active_on?(board.date) : imported.include?(car['plate'])
          raise TimeOff::UpdateDay::InvalidChange, "Placa #{car['plate']} não está disponível no cadastro ou na importação." unless allowed
          raise TimeOff::UpdateDay::InvalidChange, 'A mesma placa não pode ocupar duas saídas.' if car['scheduled'] && plates.include?(car['plate'])
          plates.add(car['plate']) if car['scheduled']
        end
        Board::ROLES.each do |role|
          id = car[role].presence
          if id
            raise TimeOff::UpdateDay::InvalidChange, 'Retire a equipe da saída cancelada ou da vaga não prevista.' unless car['scheduled'] && (role == 'driver' || role[-1].to_i <= car['helper_count'])
            member = board.member(id)
            raise TimeOff::UpdateDay::InvalidChange, 'Colaborador de folga, inativo ou indisponível. Ajuste a Escala do dia antes de alocá-lo no PCD.' unless board.eligible?(member, car, role)
            raise TimeOff::UpdateDay::InvalidChange, 'O mesmo colaborador não pode ocupar duas posições.' if people.include?(member['person_key'])
            people.add(member['person_key'])
          end
          car[role] = id
          car["#{role}_name"] = board.member(id)&.fetch('name', nil)
          car["#{role}_code"] = board.member(id)&.fetch('code', nil)
        end
        car
      end
    rescue ArgumentError, TypeError
      raise TimeOff::UpdateDay::InvalidChange, 'Composição inválida.'
    end

    def self.movements(board, before, after)
      previous = before.index_by { |car| car['key'] }
      changes = []
      after.each do |car|
        old = previous[car['key']]
        label = car['maps'].any? ? "Mapa(s) #{car['maps'].map { |m| m['number'] }.join(', ')}" : "#{TimeOff::Coverage::OPERATIONS.fetch(car['operation'])} #{car['position'].to_i + 1}"
        if !old
          changes << "#{label}: rota adicionada · #{car['plate']}"
          next
        end
        EDITABLE.each do |field|
          next if old[field] == car[field]
          title = { 'plate' => 'Placa', 'scheduled' => 'Saída prevista', 'operation' => 'Operação', 'helper_count' => 'Ajudantes', 'driver' => 'Motorista', 'helper1' => 'Ajudante 1', 'helper2' => 'Ajudante 2', 'room' => 'Sala', 'departure_time' => 'Horário', 'external_driver' => 'Motorista externo', 'external_helper1' => 'Ajudante externo 1', 'external_helper2' => 'Ajudante externo 2', 'notes' => 'Observação' }.fetch(field)
          from, to = old[field], car[field]
          if Board::ROLES.include?(field)
            from = old["#{field}_name"] || board.member(from)&.fetch('name', nil)
            to = car["#{field}_name"]
          elsif field == 'room'
            from = Board::ROOMS[from]&.first
            to = Board::ROOMS[to]&.first
          elsif field == 'scheduled'
            from = from ? 'Prevista' : 'Sem saída'
            to = to ? 'Prevista' : 'Sem saída'
          elsif field == 'operation'
            from = TimeOff::Coverage::OPERATIONS[from]
            to = TimeOff::Coverage::OPERATIONS[to]
          end
          changes << "#{label} · #{title}: #{from.presence || 'vazio'} → #{to.presence || 'vazio'}"
        end
      end
      (previous.keys - after.map { |car| car['key'] }).each { |key| changes << "#{key}: rota retirada na nova importação" }
      changes
    end
    private_class_method :persist, :validate!, :movements
  end
end
