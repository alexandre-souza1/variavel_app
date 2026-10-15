module AiAssistant
  module ManagementQueries
    private

    def list_routines(args)
      scope = Routine.visible_to(@user)
      scope = scope.where(action_plan_id: Integer(args['plan_id'])) if args['plan_id'].present?
      if args['query'].present?
        scope = scope.joins(:routine_template).where('routines.title ILIKE :q OR routine_templates.name ILIKE :q', q: search_pattern(args['query']))
      end
      if args['status'].present? && args['status'] != 'all'
        raise ArgumentError unless Routine.statuses.key?(args['status'])
        scope = scope.where(status: args['status'])
      elsif args['status'] != 'all'
        scope = scope.where.not(status: :archived)
      end
      result = paginate(scope.includes(:routine_template, :action_plan).order(period_start: :desc, id: :desc), args)
      result[:records] = result[:records].map do |routine|
        source(routine.title.presence || routine.routine_template.name, routine_path(routine))
        { id: routine.id, title: routine.title, template: routine.routine_template.name, sector: routine.sector, plan: routine.action_plan&.name,
          from: routine.period_start, to: routine.period_end, status: routine.status }
      end
      result
    end

    def routine_details(args)
      routine = Routine.visible_to(@user).find(Integer(args.fetch('routine_id')))
      indicators = routine.selected_indicators
      indicators = indicators.where('routine_indicators.name ILIKE ?', search_pattern(args['query'])) if args['query'].present?
      result = paginate(indicators, args)
      result[:records] = result[:records].map do |indicator|
        calculation = Routines::CalculationService.call(routine: routine, indicator: indicator)
        { id: indicator.id, name: indicator.name, category: indicator.routine_category.name,
          value_type: indicator.value_type, direction: indicator.goal_direction, frequency: indicator.response_frequency,
          calculation: calculation }
      end
      source(routine.title.presence || routine.routine_template.name, routine_path(routine))
      { id: routine.id, title: routine.title, from: routine.period_start, to: routine.period_end, status: routine.status, indicators: result }
    end

    def routine_values(args)
      routine = Routine.visible_to(@user).find(Integer(args.fetch('routine_id')))
      first, last = date_range(args, default_from: routine.period_start, default_to: routine.period_end)
      scope = routine.routine_values.where(routine_indicator_id: routine.selected_indicator_ids, reference_date: first..last)
      scope = scope.where(routine_indicator_id: Integer(args['indicator_id'])) if args['indicator_id'].present?
      result = paginate(scope.includes(:routine_indicator).order(:reference_date, :id), args)
      result[:records] = result[:records].map { |value| { indicator_id: value.routine_indicator_id, indicator: value.routine_indicator.name, date: value.reference_date, value: bounded_text(value.value, 1000) } }
      source(routine.title.presence || routine.routine_template.name, routine_path(routine))
      result.merge(from: first, to: last, note: 'Ausência de preenchimento não significa resultado zero.')
    end

    def list_meetings(args)
      first, last = date_range(args)
      scope = @access.meetings.where(meeting_date: first..last)
      scope = scope.where(action_plan_id: Integer(args['plan_id'])) if args['plan_id'].present?
      scope = scope.where('meeting_minutes.title ILIKE ?', search_pattern(args['query'])) if args['query'].present?
      result = paginate(scope.includes(:action_plan, :creator).order(meeting_date: :desc, id: :desc), args)
      result[:records] = result[:records].map do |meeting|
        source(meeting.title, action_plan_meeting_minute_path(meeting.action_plan_id, meeting))
        { id: meeting.id, title: meeting.title, date: meeting.meeting_date, plan: meeting.action_plan.name,
          creator: meeting.creator.name, status: meeting.status }
      end
      result.merge(from: first, to: last)
    end

    def meeting_details(args)
      meeting = @access.meetings.find(Integer(args.fetch('meeting_id')))
      source(meeting.title, action_plan_meeting_minute_path(meeting.action_plan_id, meeting))
      return { title: meeting.title, date: meeting.meeting_date, status: meeting.status, available: false } unless meeting.completed?
      { id: meeting.id, title: meeting.title, date: meeting.meeting_date, status: meeting.status, available: true,
        summary: bounded_text(meeting.summary, 6000), decisions: Array(meeting.decisions).first(30).map { |item| bounded_text(item, 800) },
        pending_items: Array(meeting.pending_items).first(30).map { |item| bounded_text(item, 800) },
        truncated: meeting.summary.to_s.length > 6000 || Array(meeting.decisions).size > 30 || Array(meeting.pending_items).size > 30 ||
          [*Array(meeting.decisions), *Array(meeting.pending_items)].any? { |item| item.to_s.length > 800 } }
    end

    def list_documents(args)
      scope = Download.all
      if args['query'].present?
        scope = scope.where('title ILIKE :q OR description ILIKE :q', q: search_pattern(args['query']))
      end
      scope = scope.where(category: args['category']) if args['category'].present?
      scope = scope.where(sector: args['sector']) if args['sector'].present?
      result = paginate(scope.order(:category, :title, :id), args)
      result[:records] = result[:records].map do |document|
        source(document.title, open_download_path(document))
        { id: document.id, title: document.title, description: bounded_text(document.description, 1000), category: document.category, sector: document.sector }
      end
      result.merge(note: 'Catálogo de documentos; o conteúdo dos anexos não foi lido. Não invente procedimentos a partir do título.')
    end

    def public_resources(args)
      case args.fetch('resource')
      when 'parking'
        layout = ParkingLayout.current
        rows = layout.visible_assignments.map { |number, plate| { slot: number, plate: plate.presence } }
        rows.select! { |row| row[:plate].to_s.downcase.include?(args['query'].to_s.downcase) } if args['query'].present?
        source('Mapa do pátio', patio_path)
        array_page(rows, args).merge(updated_at: layout.updated_at)
      when 'routes'
        rows = JSON.parse(Rails.root.join('config/rotogramas.json').read)
        if args['query'].present?
          term = I18n.transliterate(args['query'].to_s).downcase
          rows.select! { |row| I18n.transliterate(row.values_at('name', 'aliases', 'context').join(' ')).downcase.include?(term) }
        end
        source('Rotogramas', rotogramas_path)
        array_page(rows.map { |row| row.slice('id', 'name', 'context', 'pages') }, args).merge(note: 'Catálogo de rotogramas. O conteúdo dos PDFs não foi lido.')
      else raise ArgumentError
      end
    end

    def ai_usage(args)
      setting = AiSetting.current
      dashboard = GeminiUsageDashboard.new(setting)
      report = GeminiUsageReport.new(period: args['period'])
      source('Consumo de IA', edit_admin_ai_setting_path(tab: 'users', period: report.period))
      { from: report.start_at, to: report.now, summary: report.summary, by_model: report.model_data, by_feature: report.feature_data,
        people: report.users(query: args['query'], page: args['page']), primary_model: setting.primary_model,
        quotas: dashboard.cards.map { |card| { model: card[:model], metrics: card[:metrics], daily: card[:daily] } },
        note: 'Somente nomes e metadados de uso. Conversas privadas não são consultadas. Cotas são estimadas.' }
    end

    def list_accounts(args)
      scope = filter_status(User.all, args['status'], archived: :inactive)
      scope = scope.where('name ILIKE ?', search_pattern(args['query'])) if args['query'].present?
      if args['sector'].present?
        raise ArgumentError unless User.sectors.key?(args['sector'])
        scope = scope.where(sector: args['sector'])
      end
      result = paginate(scope.select(:id, :name, :email, :sector, :role, :active).order(:name, :id), args)
      result[:records] = result[:records].map { |user| { id: user.id, name: user.name, email: user.email, sector: user.sector, role: user.role, active: user.active? } }
      source('Usuários e permissões', admin_users_path)
      result
    end

    def ai_configuration(_args)
      setting = AiSetting.current
      source('Configurações de IA', edit_admin_ai_setting_path(tab: 'settings'))
      { primary_model: setting.primary_model, default_fallback_models: GeminiMeetingService::DEFAULT_FALLBACK_MODELS,
        meeting_audio_max_minutes: setting.meeting_audio_max_minutes, limits: setting.model_limits,
        configured: ENV['GEMINI_API_KEY'].present? }
    end
  end
end
