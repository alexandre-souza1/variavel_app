module AiAssistant
  module PeopleQueries
    private

    def list_employees(args)
      scope = filter_status(@access.employees, args['status'])
      sector = employee_sector(args)
      scope = scope.in_current_or_last_sector(sector) if sector
      if args['query'].present?
        scope = scope.where('nome ILIKE :q OR matricula ILIKE :q', q: search_pattern(args['query']))
      end
      roles = EmployeeRole.for_directory.where(sector: sector || @access.employee_sectors)
      roles = roles.where(cargo: args['cargo']) if args['cargo'].present?
      roles = roles.where(turno: Integer(args['turno'])) if args['turno'].present?
      scope = scope.where(id: roles.select(:employee_id)) if args['cargo'].present? || args['turno'].present?
      result = paginate(scope.order(:nome, :id), args)
      current_roles = roles.where(employee_id: result[:records].map(&:id)).index_by(&:employee_id)
      result[:records] = result[:records].map do |person|
        role = current_roles[person.id]
        source(person.nome, employee_path(person, employee_sector: sector))
        { id: person.id, name: person.nome, registration: person.matricula, active: person.active?,
          role: role&.label, sector: role&.sector, shift: role&.shift_label,
          employment_status: person.employment_status_label }
      end
      result
    end

    def employee_details(args)
      person = @access.employees.find(Integer(args.fetch('employee_id')))
      sector = employee_sector(args)
      roles = person.employee_roles.where(sector: sector || @access.employee_sectors).order(Arel.sql('starts_on DESC NULLS LAST, id DESC'))
      closings = person.variable_closings.where(sector: sector || @access.employee_sectors)
      if args['month'].present?
        month = query_month(args['month'])
        closings = closings.where(year: month.year, month: month.month)
      end
      # One entry per period and sector; revisions are not summed together.
      closings = closings.order(year: :desc, month: :desc, revision: :desc).to_a.uniq { |row| [row.sector, row.year, row.month] }
      history = paginate(roles, args)
      history[:records] = history[:records].map { |role| { role: role.label, sector: role.sector, shift: role.shift_label, from: role.starts_on, to: role.ends_on } }
      saved = array_page(closings, args)
      saved[:records] = saved[:records].map { |closing| closing_row(closing) }
      source(person.nome, employee_path(person, employee_sector: sector))
      { id: person.id, name: person.nome, registration: person.matricula, active: person.active?, roles: history, closings: saved }
    end

    def closing_row(closing)
      { year: closing.year, month: closing.month, sector: closing.sector, revision: closing.revision,
        source: closing.legacy_baseline? ? 'Referência legada; não comprova pagamento' : 'Fechamento registrado; não comprova pagamento',
        values: closing.result.slice('totals', 'groups', 'components', 'total', 'from', 'to') }
    end

    def employee_variable(args)
      person = @access.employees.find(Integer(args.fetch('employee_id')))
      sector = employee_sector(args)
      return { error: 'Informe o setor du ou az para consultar a variável, pois os fechamentos são diferentes.' } unless sector
      first, last = closing_range(args, sector: sector)
      closing = person.variable_closings.where(sector: sector, year: last.year, month: last.month).order(revision: :desc).first
      source("Variável de #{person.nome}", employee_path(person, employee_sector: sector))
      return closing_row(closing).merge(name: person.nome, from: first, to: last) if closing

      if sector == 'du'
        report = EmployeeVariableReport.new(person, from: first, to: last)
        { name: person.nome, sector: sector, from: first, to: last, source: 'Prévia calculada; não comprova pagamento',
          maps: report.maps.size, totals: report.totals, by_role: report.groups, issues: report.issues.first(20) }
      else
        report = AzVariableReport.for_period(person: person, from: first, to: last)
        { name: person.nome, sector: sector, from: first, to: last, source: 'Prévia calculada; não comprova pagamento',
          total: report.total, components: AzVariableReport::COMPONENTS.to_h { |key| [key, report.component(key)] }, issues: report.issues.first(20) }
      end
    end

    def employee_feedbacks(args)
      person = @access.employees.find(Integer(args.fetch('employee_id')))
      year = Integer(args.fetch('year', Date.current.year))
      raise ArgumentError unless (2000..2100).cover?(year)
      identity = PublicVariableIdentity.new('colaborador', person)
      scope = PeopleCycleFeedback.for_identity(identity).where(cycle: year.to_s)
      result = paginate(scope, args)
      result[:records] = result[:records].map { |feedback| { cycle: feedback.cycle, stage: feedback.stage, response: bounded_text(feedback.response, 4000) } }
      source("Cadastro de #{person.nome}", employee_path(person))
      result.merge(name: person.nome, year: year)
    end

    def time_off(args)
      return { error: 'Seu perfil não possui acesso ao cadastro de colaboradores.' } unless @access.allowed?(:employees)
      person = @access.employees.find(Integer(args.fetch('employee_id')))
      date = query_date(args['date'])
      month = query_month(args['month'], default: date)
      return { error: 'A escala de folgas consultada é do setor DU.' } unless person.employee_roles.du.exists?
      source("Escala de #{person.nome}", time_off_schedule_path(date: date, month: month.strftime('%Y-%m'), name: person.nome))
      TimeOff::PersonalSchedule.new(person: person, today: date, month: month.strftime('%Y-%m')).call.merge(name: person.nome)
    end

    def time_off_team(args)
      date = query_date(args['date'])
      schedule = TimeOffSchedule.order(:id).first
      return { available: false, date: date, message: 'Não há escala cadastrada.' } unless schedule
      members = schedule.time_off_memberships.with_active_people.on(date).includes(:employee, :driver, :ajudante).to_a
      availability = TimeOff::Availability.new(schedule: schedule, first: date, last: date)
      records = members.filter_map do |member|
        person = member.employee || member.person
        next if args['query'].present? && !person.nome.to_s.downcase.include?(args['query'].to_s.downcase)
        status = availability.status(member, date)
        next if status.nil?
        { name: person.nome, role: member.role_label(date), group: member.group_code, status: status, label: TimeOffSchedule::STATUSES[status] }
      end
      counts = records.group_by { |row| row[:status] }.transform_values(&:size)
      if args['status'].present?
        raise ArgumentError unless TimeOffSchedule::STATUSES.key?(args['status'])
        records.select! { |row| row[:status] == args['status'] }
      end
      source('Escala de folgas', time_off_schedule_path(date: date))
      array_page(records.sort_by { |row| row[:name] }, args).merge(date: date, counts: counts, available: true)
    end
  end
end
