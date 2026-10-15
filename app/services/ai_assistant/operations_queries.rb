module AiAssistant
  module OperationsQueries
    private

    def du_summary(args)
      first, last = closing_range(args)
      years = (first.year..last.year).to_a
      scope = Mapa.where(years.map { 'data LIKE ?' }.join(' OR '), *years.map { |year| "%#{year}" })
      maps = scope.to_a.select { |map| map.data_formatada&.between?(first, last) }
      regular = maps.reject { |map| map.recarga == 'SIM' }
      devolution = DuDevolutionReport.new(maps)
      ranking = %i[driver helper].flat_map do |profile|
        devolution.ranking(profile, limit: nil).map { |row| row.except(:person).merge(name: row[:person][:name], profile: profile) }
      end
      source('Dashboard DU', dashboard_mapas_path(mes: last.month, ano: last.year))
      { from: first, to: last, maps: maps.size, refills: maps.size - regular.size,
        boxes: regular.sum { |map| map.cx_real.to_f }, delivered_points: regular.sum { |map| map.pdv_real.to_f },
        devolution: devolution.general, ignored_maps: devolution.ignored_maps_count,
        devolution_ranking: array_page(ranking.sort_by { |row| -row[:percentage] }, args),
        partial: last > Date.current, note: 'Indicadores operacionais; devolução não determina sozinha o bônus nem comprova pagamento.' }
    end

    def az_summary(args)
      first, last = closing_range(args, sector: 'az')
      shift = Integer(args['turno']) if args['turno'].present?
      raise ArgumentError if shift && ![0, 1, 2].include?(shift)
      report = AzDashboardService.new(start_date: first, end_date: last, turno: shift).call
      people = [*report.operators.map { |row| row.merge(profile: 'operador') }, *report.helpers.map { |row| row.merge(profile: 'ajudante') }]
      rows = people.map { |row| row.except(:person).merge(name: row[:person].nome) }
      source('Dashboard Armazém', dashboard_az_path(mes: last.month, ano: last.year, turno: shift))
      { from: first, to: last, shift: shift, indicators: report.indicators, daily: report.daily,
        total_operators: report.operators.sum { |row| row[:total] }, total_helpers: report.helpers.sum { |row| row[:total] },
        ranking: array_page(rows.sort_by { |row| -row[:total] }, args), partial: last > Date.current,
        note: 'Valores do relatório do Armazém; não comprovam pagamento.' }
    end

    def fuel_consumption(args)
      first, last = closing_range(args)
      report = Gasola::TeamReport.new(from: first, to: last, registration: args['registration'], plate: args['plate'], fuel: args['fuel'])
      source('Consumo de combustível', fuel_consumptions_path(from: first, to: last, registration: args['registration'], plate: args['plate']))
      { from: first, to: last, totals: report.totals, emissions: report.emissions, complete: report.complete?,
        updated_at: report.sync&.created_at, by_driver: array_page(report.by_driver, args), by_plate: array_page(report.by_plate, args),
        note: 'Consumo Gasola; a ausência de dados não significa média zero. Não altera o pagamento da variável.' }
    end

    def list_plates(args)
      scope = filter_status(Plate.all, args['status'], archived: :inactive)
      scope = scope.where('placa ILIKE ?', search_pattern(args['query'])) if args['query'].present?
      scope = scope.where(setor: args['sector']) if args['sector'].present?
      result = paginate(scope.order(:placa, :id), args)
      result[:records] = result[:records].map do |plate|
        source(plate.placa, plate_path(plate))
        { id: plate.id, plate: plate.placa, sector: plate.setor, type: plate.tipo, profile: plate.perfil, active: plate.active? }
      end
      result
    end

    def fleet_dimensioning(args)
      date = query_date(args['date'])
      setting = FleetDimensioning.for_date(date)
      return { available: false, date: date, message: 'Não há dimensionamento cadastrado nesta data.' } unless setting
      source('Dimensionamento da frota', fleet_dimensionings_path)
      { available: true, date: date, label: setting.label, from: setting.start_date, to: setting.end_date,
        route: setting.route_quantity, van: setting.van_quantity, afternoon: setting.vespertina_quantity, as: setting.as_quantity,
        standard_plates: setting.fleet_dimensioning_standard_plates.includes(:plate).map { |slot| { position: slot.position, route: slot.special_route, plate: slot.plate&.placa } } }
    end

    def tire_status(args)
      client = Prolog::TiresClient.new
      tires = args['plate'].present? ? client.tires_for_plate(args['plate']) : client.tires_needing_retread
      return { available: false, error: 'A consulta de pneus está indisponível na Prolog. Confira a integração na tela de pneus.' } if client.error.present?
      source('Pneus', tire_inspections_path)
      rows = tires.map { |tire| tire.slice(:id, :fire_number, :plate, :position, :life, :spare, :smallest_tread_depth, :created_at) }
      array_page(rows, args).merge(available: true, source: 'Prolog', consulted_at: Time.current, retread_threshold_mm: 3.5)
    end

    def stress_events(args)
      first, last = date_range(args)
      scope = StressTestEvent.where(operation_date: first..last)
      if args['query'].present?
        scope = scope.where('placa ILIKE :q OR motorista ILIKE :q OR mapa ILIKE :q OR destino ILIKE :q', q: search_pattern(args['query']))
      end
      result = paginate(scope.order(operation_date: :desc, operation_time: :desc, id: :desc), args)
      result[:records] = result[:records].map do |event|
        source("Stress Test #{event.operation_date}", import_details_stress_test_path(event.stress_test_import_id))
        { plate: event.placa, map: event.mapa, phase: event.fase, date: event.operation_date, time: event.operation_time&.strftime('%H:%M'), driver: event.motorista, destination: event.destino }
      end
      result.merge(from: first, to: last)
    end

    def list_checklists(args)
      first, last = date_range(args)
      scope = checklist_scope.where(created_at: first.in_time_zone..last.in_time_zone.end_of_day)
      if args['plate'].present?
        scope = scope.left_joins(:plate).where('plates.placa ILIKE :q OR checklists.placa_manual ILIKE :q', q: search_pattern(args['plate']))
      end
      if args['status'].present?
        raise ArgumentError unless Checklist.statuses.key?(args['status'])
        scope = scope.where(status: args['status'])
      end
      result = paginate(scope.includes(:plate, :user, :checklist_template).order(created_at: :desc, id: :desc), args)
      result[:records] = result[:records].map { |record| checklist_row(record) }
      result.merge(from: first, to: last)
    end

    def checklist_row(record)
      source("Checklist #{record.id}", checklist_path(record))
      { id: record.id, template: record.checklist_template.name, status: record.status, plate: record.plate&.placa || record.placa_manual,
        responsible: record.responsavel, author: record.user.name, created_at: record.created_at }
    end

    def checklist_details(args)
      record = checklist_scope.includes(:plate, :user, :checklist_template).find(Integer(args.fetch('checklist_id')))
      responses = paginate(record.checklist_responses.includes(:checklist_item).order(:id), args)
      responses[:records] = responses[:records].map { |row| { item: row.checklist_item.description, status: row.status, comment: bounded_text(row.comment, 800) } }
      defects = paginate(record.checklist_defects.order(:id), args)
      defects[:records] = defects[:records].map { |row| { location: row.location, description: bounded_text(row.description, 800) } }
      checklist_row(record).merge(observation: bounded_text(record.observation), kilometer: record.kilometer, origin: record.origin,
        responses: responses, defects: defects)
    end

    def pcd_board(args)
      date = query_date(args['date'])
      board = Pcd::Board.new(date: date)
      cars = board.cars.select { |car| car['scheduled'] }.map do |car|
        people = Pcd::Board::ROLES.to_h { |role| [role, board.member(car[role])&.fetch('name', nil)] }
        car.slice('plate', 'operation', 'room', 'departure_time', 'helper_count', 'external_driver', 'external_helper1', 'external_helper2').merge(people)
      end
      source('PCD SALAS', pcd_path(date: date))
      { date: date, saved: board.plan.present?, updated_at: board.plan&.updated_at, metrics: board.metrics, cars: array_page(cars, args),
        note: board.plan ? 'PCD salvo; confira alterações na tela.' : 'Prévia calculada; não há PCD salvo nesta data.' }
    end
  end
end
