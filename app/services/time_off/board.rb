module TimeOff
  class Board
    ROLES = %w[driver helper1 helper2].freeze
    attr_reader :coverage

    def initialize(coverage)
      @coverage = coverage
    end

    def cars
      @cars ||= begin
        plates = coverage.dimensioning&.standard_plate_by_position || {}
        special_plates = coverage.dimensioning&.standard_plate_by_special_route || {}
        slots = coverage.quantities.flat_map do |operation, quantity|
          Array.new(quantity) do |position|
            plate = operation == 'route' ? plates[position]&.plate : special_plates[operation]&.plate
            { 'key' => "#{operation}:#{position}", 'operation' => operation, 'position' => position,
              'plate' => plate && RoutingCsv.plate(plate.placa), 'scheduled' => true,
              'label' => plate&.placa || "#{operation == 'route' ? 'Carro' : Coverage::OPERATIONS[operation]} #{position + 1}",
              'helper_count' => %w[route vespertina].include?(operation) ? 1 : 0,
              'driver' => nil, 'helper1' => nil, 'helper2' => nil }
          end
        end
        saved = coverage.details['cars']
        saved ? restore(slots, saved) : suggest(slots)
        slots.each { |car| car['label'] = car['plate'].presence || (coverage.details['routing_import'] ? 'Sem placa definida' : car['label']) }
        slots
      end
    end

    def members
      coverage.members.uniq(&:person_key)
    end

    def pools
      used = cars.flat_map { |car| ROLES.map { |role| car[role] } }.compact
      members.reject { |m| used.include?(m.id) }.group_by do |m|
        status = coverage.status(m)
        status == 'dsr' ? 'off' : status == 'vacation' ? 'unavailable' : status
      end
    end

    def state
      { cars: cars, routing_import: coverage.details['routing_import'], members: members.map { |m| {
        id: m.id, name: m.person.nome, group: m.group_code, cargo: m.cargo_on(coverage.date),
        membership_role: m.role,
        role: EmployeeRole::CARGOS.key(m.cargo_on(coverage.date)) || m.role_label,
        active: m.active_person?,
        status: coverage.status(m), revision: coverage.revision(m), vacation: coverage.status(m) == 'vacation'
      } } }
    end

    def metrics
      { dimensioned_cars: cars.size, cars: scheduled_cars.size, drivers: scheduled_cars.count { |c| c['driver'] }, driver_gap: scheduled_cars.count { |c| !c['driver'] },
        helper_gap: scheduled_cars.sum { |c| (1..c['helper_count']).count { |n| !c["helper#{n}"] } } }
    end

    def scheduled_cars
      cars.select { |car| car['scheduled'] }
    end

    def self.validate!(coverage, raw_cars)
      raise UpdateDay::InvalidChange, 'Envie todos os carros do painel.' unless raw_cars.is_a?(Array)
      expected = coverage.quantities.flat_map { |op, qty| Array.new(qty) { |i| [op, i] } }
      used = Set.new
      used_plates = Set.new
      imported_plates = Array(coverage.details.dig('routing_import', 'rows')).map { |row| row['plate'] }
      known_plates = Plate.all.index_by { |plate| RoutingCsv.plate(plate.placa) }
      defaults = new(coverage).cars.index_by { |car| [car['operation'], car['position']] }
      normalized = raw_cars.map do |raw|
        raise UpdateDay::InvalidChange, 'Carro inválido.' unless raw.is_a?(Hash)
        raw = raw.stringify_keys
        operation = raw['operation']
        position = Integer(raw['position'].to_s, 10)
        count = Integer(raw['helper_count'].to_s, 10)
        valid_count = operation == 'route' ? (0..2).cover?(count) : count == (operation == 'vespertina' ? 1 : 0)
        raise UpdateDay::InvalidChange, 'Composição incompatível com esta operação.' unless valid_count && expected.include?([operation, position])
        default = defaults.fetch([operation, position])
        scheduled = raw.key?('scheduled') ? ActiveModel::Type::Boolean.new.cast(raw['scheduled']) : true
        plate = raw.key?('plate') ? RoutingCsv.plate(raw['plate']).presence : default['plate']
        if plate
          known = known_plates[plate]
          allowed = known ? known.active_on?(coverage.date) : imported_plates.include?(plate)
          raise UpdateDay::InvalidChange, "Placa #{plate} não está disponível no cadastro ou no CSV importado." unless allowed
          raise UpdateDay::InvalidChange, 'A mesma placa não pode ocupar duas saídas no dia.' if scheduled && used_plates.include?(plate)
          used_plates.add(plate) if scheduled
        end
        car = { 'operation' => operation, 'position' => position, 'helper_count' => count, 'plate' => plate, 'scheduled' => scheduled }
        ROLES.each do |role|
          id = raw[role].presence
          raise UpdateDay::InvalidChange, 'Retire os colaboradores antes de marcar a posição sem saída.' if id && !scheduled
          if role.start_with?('helper') && role.delete_prefix('helper').to_i > count && id
            raise UpdateDay::InvalidChange, 'Retire o ajudante antes de reduzir a composição do carro.'
          end
          person = id ? coverage.member(id) : nil
          if id && (!person || !coverage.eligible?(person, operation: operation, role: role == 'driver' ? 'driver' : 'helper'))
            raise UpdateDay::InvalidChange, operation == 'van' && role == 'driver' ? 'Van exige o cargo Motorista de van vigente e disponibilidade no dia.' : 'Colaborador indisponível ou com cargo incompatível para esta posição.'
          end
          if person && used.include?(person.person_key)
            raise UpdateDay::InvalidChange, 'O mesmo colaborador não pode ocupar duas posições no dia.'
          end
          used.add(person.person_key) if person
          car[role] = person&.id
        end
        car
      end
      unless normalized.map { |c| [c['operation'], c['position']] }.sort == expected.sort
        raise UpdateDay::InvalidChange, 'O painel deve conter exatamente os carros dimensionados, sem posições repetidas.'
      end
      normalized
    rescue ArgumentError, TypeError
      raise UpdateDay::InvalidChange, 'Informe posições e quantidades válidas para os carros.'
    end

    private

    def restore(slots, saved)
      used = Set.new
      by_position = saved.index_by { |c| [c['operation'], c['position']] }
      slots.each do |car|
        previous = by_position[[car['operation'], car['position']]]
        next unless previous
        car['plate'] = previous['plate'] if previous.key?('plate')
        car['scheduled'] = previous.fetch('scheduled', true)
        car['helper_count'] = previous['helper_count'] if car['operation'] == 'route'
        next unless car['scheduled']
        ROLES.each do |role|
          m = coverage.member(previous[role])
          next unless m && !used.include?(m.person_key) && coverage.eligible?(m, operation: car['operation'], role: role == 'driver' ? 'driver' : 'helper')
          next if role != 'driver' && role.delete_prefix('helper').to_i > car['helper_count']
          car[role] = m.id
          used.add(m.person_key)
        end
      end
    end

    def suggest(slots)
      used = Set.new
      slots.reject { |c| c['operation'] == 'route' }.each do |car|
        { 'driver' => 'driver', 'helper1' => 'helper' }.each do |role, default_role|
          next if role == 'helper1' && car['helper_count'].zero?
          m = coverage.assignments.dig(car['operation'], default_role)&.[](car['position'])
          place(car, role, m, used)
        end
      end
      routes = slots.select { |c| c['operation'] == 'route' }
      routes.each_with_index do |car, i|
        car['helper_count'] = i < coverage.solo_routes ? 0 : i < coverage.solo_routes + coverage.double_helper_routes ? 2 : 1
      end
      # The first three pairs in each supplied group are the titular crews.
      # Pilot keys retain the original pair even after a dated group transfer.
      original = coverage.schedule.time_off_memberships.where.not(pilot_key: nil).includes(:driver, :ajudante).index_by(&:person_key)
      members.each do |m|
        key = m.pilot_key || original[m.person_key]&.pilot_key
        match = /\A([A-F])-([1-6])\z/.match(key.to_s)
        next unless match
        position = TimeOffSchedule::ROTATING_GROUPS.index(match[1]) * 3 + (match[2].to_i - 1) / 2
        car = routes[position]
        next unless car
        role = match[2].to_i.odd? ? 'driver' : 'helper1'
        next if role == 'helper1' && (car['helper_count'].zero? || m.cargo_on(coverage.date) != 'ajudante')
        place(car, role, m, used)
      end
      candidates = members.sort_by { |m| [m.group_code, m.person.nome] }
      routes.each do |car|
        next if car['driver']
        m = candidates.find { |p| !used.include?(p.person_key) && !coverage.helper_drivers.include?(p) && coverage.eligible?(p, operation: 'route', role: 'driver') }
        place(car, 'driver', m, used)
      end
      helper_candidates = candidates.select { |m| m.cargo_on(coverage.date) == 'ajudante' } + coverage.helper_drivers
      routes.each do |car|
        (1..car['helper_count']).each do |n|
          role = "helper#{n}"
          next if car[role]
          m = helper_candidates.find { |p| !used.include?(p.person_key) && coverage.eligible?(p, operation: 'route', role: 'helper') }
          place(car, role, m, used)
        end
      end
    end

    def place(car, role, m, used)
      return unless m && !used.include?(m.person_key) && coverage.eligible?(m, operation: car['operation'], role: role == 'driver' ? 'driver' : 'helper')
      car[role] = m.id
      used.add(m.person_key)
    end
  end
end
