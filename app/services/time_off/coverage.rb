module TimeOff
  class Coverage
    OPERATIONS = { 'route' => 'Rota padrão', 'vespertina' => 'Vespertina', 'as' => 'AS', 'van' => 'Van' }.freeze
    SPECIAL_OPERATIONS = OPERATIONS.keys - ['route']
    attr_reader :schedule, :date, :dimensioning, :plan, :members, :details

    def initialize(schedule:, date:, details: nil)
      @schedule, @date = schedule, date
      @dimensioning = FleetDimensioning.for_date(date)
      @plan = schedule.time_off_daily_plans.find_by(date: date)
      @details = (details || plan&.details || {}).deep_stringify_keys
      @members = schedule.time_off_memberships.with_active_people.on(date).includes(driver: { employee: :employee_roles }, ajudante: { employee: :employee_roles }).order(:id).to_a
      @overrides = TimeOffOverride.where(time_off_membership_id: members.map(&:id), date: date).index_by(&:time_off_membership_id)
      @availability = Availability.new(schedule: schedule, first: date)
    end

    def editable?
      dimensioning && schedule.covers?(date) && !date.sunday?
    end

    def quantities
      return OPERATIONS.keys.index_with { 0 } unless dimensioning && schedule.covers?(date) && !date.sunday?
      { 'route' => dimensioning.route_quantity.to_i,
        'vespertina' => date.saturday? ? 0 : dimensioning.vespertina_quantity.to_i,
        'as' => date.saturday? ? 0 : dimensioning.as_quantity.to_i,
        'van' => date.saturday? ? 0 : dimensioning.van_quantity.to_i }
    end

    def signature
      return unless dimensioning
      Digest::SHA256.hexdigest([dimensioning.id, dimensioning.start_date, dimensioning.end_date,
        dimensioning.route_quantity, dimensioning.vespertina_quantity, dimensioning.as_quantity, dimensioning.van_quantity,
        dimensioning.fleet_dimensioning_standard_plates.reorder(:special_route, :position, :plate_id).pluck(:position, :special_route, :plate_id)].to_json)
    end

    def stale?
      plan && plan.dimensioning_signature != signature
    end

    def status(member)
      @availability.status(member, date)
    end

    def revision(member)
      @overrides[member.id]&.lock_version || -1
    end

    def available?(member)
      member && member.active_person? && status(member) == 'working'
    end

    def eligible?(member, operation:, role:)
      return false unless available?(member)
      cargo = member.cargo_on(date)
      return %w[ajudante motorista van].include?(cargo) if role == 'helper'
      operation == 'van' ? cargo == 'van' : cargo == 'motorista'
    end

    def member(id)
      return if id.blank?
      members.find { |m| m.id == id.to_i } || begin
        # A dated group change retains this person's future daily decisions.
        previous = schedule.time_off_memberships.includes(:driver, :ajudante).find_by(id: id)
        members.find { |m| m.person_key == previous.person_key } if previous
      end
    end

    def default_members(operation, role)
      candidates = members.select do |m|
        m.role == role && (operation == 'van' ? m.cargo_on(date) == 'van' : m.standard_operation == operation)
      end
      candidates.uniq(&:person_key).first(quantities.fetch(operation))
    end

    def assignments
      @assignments ||= SPECIAL_OPERATIONS.index_with do |operation|
        roles = operation == 'vespertina' ? %w[driver helper] : ['driver']
        roles.index_with do |role|
          saved = details.dig('special_assignments', operation, role)
          ids = saved.nil? ? default_members(operation, role).map(&:id) : Array(saved)
          Array.new(quantities.fetch(operation)) { |index| member(ids[index]) }
        end
      end
    end

    def solo_routes
      details.fetch('solo_routes', 0).to_i
    end

    def double_helper_routes
      details.fetch('double_helper_routes', 0).to_i
    end

    def helper_drivers
      Array(details['helper_driver_ids']).filter_map { |id| member(id) }.uniq(&:person_key)
    end

    def reserved_keys
      assignments.values.flat_map { |roles| roles.values.flatten }.compact.map(&:person_key)
    end

    def helper_driver_candidates
      members.select { |m| m.role == 'driver' && eligible?(m, operation: 'route', role: 'helper') && !reserved_keys.include?(m.person_key) }.uniq(&:person_key)
    end

    def rows
      used = Set.new
      special_rows = SPECIAL_OPERATIONS.map do |operation|
        supplied = assignments.fetch(operation).each_with_object({}) do |(role, assigned), result|
          result[role] = assigned.count do |m|
            valid = m && !used.include?(m.person_key) && eligible?(m, operation: operation, role: role)
            used.add(m.person_key) if valid
            valid
          end
        end
        build_row(operation, quantities[operation], supplied['driver'].to_i,
          operation == 'vespertina' ? quantities[operation] : 0, supplied['helper'].to_i)
      end
      # A configured fixed person with a pending absence cannot inflate the
      # route pool. Reserve each position once, independently of availability.
      used.merge(reserved_keys)
      acting_helpers = helper_drivers.select { |m| eligible?(m, operation: 'route', role: 'helper') && !used.include?(m.person_key) }
      used.merge(acting_helpers.map(&:person_key))
      remaining = members.select { |m| available?(m) && !used.include?(m.person_key) }.uniq(&:person_key)
      drivers = remaining.count { |m| eligible?(m, operation: 'route', role: 'driver') }
      helpers = remaining.count { |m| m.cargo_on(date) == 'ajudante' } + acting_helpers.size
      need = [quantities['route'] - solo_routes, 0].max + double_helper_routes
      [build_row('route', quantities['route'], drivers, need, helpers), *special_rows]
    end

    def warnings
      messages = []
      messages << 'O dimensionamento mudou. Revise e salve novamente a composição deste dia.' if stale?
      messages << 'A composição salva excede as rotas previstas. Ajuste as saídas sem ajudante ou com dois ajudantes.' if solo_routes + double_helper_routes > quantities['route']
      assignments.each do |operation, roles|
        roles.each do |role, assigned|
          assigned.compact.each do |m|
            messages << "#{m.person.nome}: indisponível ou com cargo incompatível para #{OPERATIONS[operation]} (#{role == 'driver' ? 'motorista' : 'ajudante'})." unless eligible?(m, operation: operation, role: role)
          end
        end
      end
      helper_drivers.each do |m|
        messages << "#{m.person.nome}: revise a atuação como ajudante; há indisponibilidade ou alocação em operação fixa." unless eligible?(m, operation: 'route', role: 'helper') && !reserved_keys.include?(m.person_key)
      end
      messages
    end

    def summary
      names = helper_drivers.map { |m| m.person.nome }.join(', ')
      fixed = assignments.filter_map do |operation, roles|
        next if quantities[operation].zero?
        "#{OPERATIONS[operation]}: #{roles.values.flatten.map { |m| m&.person&.nome || 'vaga sem cobertura' }.join(', ')}"
      end.join('; ')
      "Rotas sem ajudante: #{solo_routes}; com dois ajudantes: #{double_helper_routes}. Motoristas como ajudantes: #{names.presence || 'nenhum'}. #{fixed}"
    end

    private

    def build_row(operation, demand, drivers, helper_need, helpers)
      { operation: operation, label: OPERATIONS.fetch(operation), demand: demand,
        drivers: drivers, driver_gap: [demand - drivers, 0].max,
        helper_need: helper_need, helpers: helpers, helper_gap: [helper_need - helpers, 0].max }
    end
  end
end
