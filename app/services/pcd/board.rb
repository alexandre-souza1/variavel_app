module Pcd
  class Board
    ROLES = %w[driver helper1 helper2].freeze
    ROOMS = {
      'room1' => ['Sala 01 · Rota', '07:00'], 'room2' => ['Sala 02 · Rota', '08:00'],
      'as' => ['Sala 03 · ASCD', '08:00'], 'vespertina' => ['Sala 04 · Vespertina', '12:00'],
      'spot' => ['SPOT · Freteiros', '06:00']
    }.freeze
    attr_reader :date, :plan, :schedule, :dimensioning

    def initialize(date:, plan: nil, cars: nil)
      @date = date
      @plan = plan || PcdPlan.find_by(date: date)
      @schedule = TimeOffSchedule.order(:id).first
      @dimensioning = FleetDimensioning.for_date(date)
      @submitted_cars = cars
    end

    def members
      @members ||= begin
        memberships = schedule ? schedule.time_off_memberships.with_active_people.on(date).includes(:driver, :ajudante).to_a : []
        by_person = memberships.index_by { |m| [m.role == 'driver' ? 'driver' : 'helper', m.person.id] }
        availability = TimeOff::Availability.new(schedule: schedule, first: date) if schedule
        records = [['driver', Driver], ['helper', Ajudante]].flat_map do |type, klass|
          TimeOff::People.active_records(klass).includes(employee: :employee_roles).map do |person|
            member = by_person[[type, person.id]]
            cargo = person.employee ? person.employee.role_on(date)&.cargo : (type == 'driver' ? 'motorista' : 'ajudante')
            status = member && availability.status(member, date)
            { 'id' => "#{type}:#{person.id}", 'name' => person.nome, 'code' => person.promax,
              'person_key' => person.employee_id ? "employee:#{person.employee_id}" : "#{type}:#{person.id}",
              'cargo' => cargo, 'group' => member&.group_code, 'status' => status || 'working',
              'role' => cargo == 'ajudante' ? 'helper' : 'driver', 'has_schedule' => status.present? }
          end
        end
        records.select { |m| %w[motorista ajudante van].include?(m['cargo']) }.uniq { |m| m['person_key'] }.sort_by { |m| [m['role'], m['name'].to_s] }
      end
    end

    def member(id)
      members.find { |m| m['id'] == id }
    end

    def cars
      @cars ||= begin
        source = @submitted_cars || plan&.details&.fetch('cars', nil) || initial_cars
        used = Set.new
        source.deep_dup.map do |car|
          car = defaults(car)
          ROLES.each do |role|
            person = member(car[role])
            valid = car['scheduled'] && person && person['status'] == 'working' && !used.include?(person['person_key']) && eligible?(person, car, role)
            car[role] = nil unless valid
            used.add(person['person_key']) if valid
          end
          car
        end
      end
    end

    def defaults(car)
      room = car['freight'] ? 'spot' : car['operation'] == 'as' ? 'as' : car['operation'] == 'vespertina' ? 'vespertina' : 'room2'
      { 'maps' => [], 'freight' => false, 'scheduled' => true, 'plate' => nil,
        'driver' => nil, 'helper1' => nil, 'helper2' => nil, 'helper_count' => 1,
        'room' => room, 'departure_time' => ROOMS.fetch(room).last, 'external_driver' => '', 'external_driver_code' => '', 'external_helper1' => '', 'external_helper2' => '', 'notes' => '' }.merge(car)
    end

    def state
      { cars: cars, members: members }
    end

    def eligible?(person, car, role)
      return false unless person && person['status'] == 'working'
      return %w[ajudante motorista van].include?(person['cargo']) unless role == 'driver'
      car['operation'] == 'van' ? person['cargo'] == 'van' : %w[motorista van].include?(person['cargo'])
    end

    def metrics
      scheduled = cars.select { |c| c['scheduled'] }
      own = scheduled.reject { |c| c['freight'] }
      { total: scheduled.size, own: own.size, freight: scheduled.count { |c| c['freight'] },
        driver_gap: own.count { |c| c['driver'].blank? },
        helper_gap: own.sum { |c| (1..c['helper_count']).count { |i| c["helper#{i}"].blank? } } }
    end

    def initial_cars
      return [] unless dimensioning && !date.sunday?
      if !schedule || !schedule.covers?(date)
        quantities = { 'route' => dimensioning.route_quantity, 'vespertina' => date.saturday? ? 0 : dimensioning.vespertina_quantity, 'as' => date.saturday? ? 0 : dimensioning.as_quantity, 'van' => date.saturday? ? 0 : dimensioning.van_quantity }
        return quantities.flat_map { |op, count| Array.new(count) { |i| defaults('key' => "#{op}:#{i}", 'position' => i, 'operation' => op, 'helper_count' => %w[route vespertina].include?(op) ? 1 : 0) } }
      end
      legacy = TimeOff::Board.new(TimeOff::Coverage.new(schedule: schedule, date: date))
      legacy.cars.map do |car|
        result = car.deep_dup
        ROLES.each do |role|
          m = car[role] ? legacy.coverage.member(car[role]) : nil
          result[role] = m && "#{m.role == 'driver' ? 'driver' : 'helper'}:#{m.person.id}"
        end
        imported = Array(legacy.coverage.details.dig('routing_import', 'rows')).find { |row| row['plate'] == car['plate'] }
        if imported
          result['maps'] = imported['maps'].map { |number| { 'number' => number, 'cities' => '', 'region' => '' } }
          result['imported_plate'] = imported['plate']
          result['external_driver_code'] = imported['driver_code']
        end
        defaults(result)
      end
    end
  end
end
