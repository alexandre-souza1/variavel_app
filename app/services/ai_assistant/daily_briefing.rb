module AiAssistant
  module DailyBriefing
    private

    def daily_briefing(args)
      focus = args['sector'].presence || @user.sector.presence || 'all'
      raise ArgumentError unless [*User.sectors.keys, 'all'].include?(focus)
      return { error: 'O resumo de outro setor é restrito à administração.' } if !@user.admin? && focus != @user.sector
      today = Date.current
      result = { date: today, generated_at: Time.current, sector: focus, personal_tasks: briefing_tasks(today), sections: {} }
      areas = result[:sections]
      areas[:indicators] = briefing_indicators(today, focus) if @access.allowed?(:routines)
      areas[:finance] = briefing_finance(today, focus) if @access.allowed?(:finance)
      if %w[fleet all].include?(focus) && @access.allowed?(:availability)
        areas[:fleet] = briefing_fleet(today)
      end
      if %w[fleet safety du all].include?(focus) && @access.allowed?(:tires)
        areas[:tires] = tire_status({})
      end
      if %w[du planning all].include?(focus) && @access.allowed?(:du)
        areas[:delivery] = du_summary({})
      end
      if %w[warehouse all].include?(focus) && @access.allowed?(:az)
        areas[:warehouse] = az_summary({})
      end
      if %w[fleet du safety all].include?(focus) && @access.allowed?(:consumption)
        areas[:consumption] = briefing_consumption
      end
      if %w[fleet safety all].include?(focus) && @access.allowed?(:stress)
        areas[:vehicle_movements] = stress_events({ 'from' => today.iso8601, 'to' => today.iso8601 })
      end
      if %w[du hr planning safety all].include?(focus) && @access.allowed?(:time_off)
        areas[:team_schedule] = time_off_team({ 'date' => today.iso8601 }).except(:records)
      end
      areas[:pcd] = pcd_board({ 'date' => today.iso8601 }) if %w[du all].include?(focus) && @access.allowed?(:pcd)
      if %w[hr du warehouse planning all].include?(focus) && @access.allowed?(:employees)
        areas[:people] = briefing_people(today, focus)
      end
      result[:note] = 'Resumo somente dos dados e módulos autorizados. Metas financeiras usam mês civil; DU e consumo fecham de 21 a 20, AZ de 19 a 18. Valores e vencimentos não comprovam pagamento. Consulte os registros para detalhes.'
      result
    end

    def briefing_tasks(today)
      mine = Task.accessible_to(@user).where(id: TaskAssignment.where(user_id: @user.id).select(:task_id))
        .or(Task.accessible_to(@user).where(creator_id: @user.id, buckets: { inbox: true, user_id: @user.id }))
      open = mine.where(completed: [false, nil])
      overdue = open.where('due_at < ?', Time.current)
      due_today = open.where(due_at: today.all_day)
      due_soon = open.where(due_at: today.next_day.in_time_zone...((today + 7).next_day.in_time_zone))
      # Reuse authorized task links while including personal inbox items in the agenda.
      result = paginate(overdue.or(due_today).includes(:users, bucket: :action_plan).order(:due_at, :id), {})
      result[:records] = result[:records].map do |task|
        path = task.inbox? ? inbox_path : @user.mechanical? ? mechanic_tasks_path(q: task.title) : action_plan_path(task.bucket.action_plan_id, task_id: task.id)
        source(task.title, path)
        { title: task.title, due_at: task.due_at, plan: task.bucket.action_plan&.name, inbox: task.inbox?,
          priority: task.due_at < Time.current ? 'overdue' : 'today' }
      end
      result.merge(overdue: overdue.count, due_today: due_today.count, due_next_7_days: due_soon.count,
        note: 'Itens atribuídos a você e sua Entrada pessoal. Vencidas inclui prazos já ultrapassados hoje; os contadores de vencidas e de hoje podem se sobrepor. O total da lista não duplica tarefas.')
    end

    def briefing_finance(today, focus)
      scope = @access.invoices
      sectors = focus == 'all' || focus == 'finance' ? nil : User::CATEGORY_SECTORS_BY_USER_SECTOR[focus.to_sym]
      scope = scope.joins(:budget_category).where(budget_categories: { sector: sectors }) if sectors
      month_scope = scope.where(date_issued: today.beginning_of_month..today.end_of_month)
      goals = InvoiceGoal.effective_on(today)
      allowed_sectors = @user.admin? || @user.sector_finance? ? BudgetCategory.sectors.keys : @user.budget_sectors
      goals = goals.where(sector: allowed_sectors)
      goals = goals.where(sector: sectors) if sectors
      entries = goals.includes(:budget_categories).order(:sector, :name, :id).map do |goal|
        spent = month_scope.where(budget_category_id: goal.budget_category_ids).sum(:total)
        { name: goal.name, sector: goal.sector, target: goal.target_amount, spent: spent,
          remaining: goal.target_amount - spent, exceeded: spent > goal.target_amount,
          percentage: (spent / goal.target_amount * 100).round(1) }
      end
      entries.sort_by! { |entry| [entry[:exceeded] ? 0 : 1, entry[:remaining], entry[:name]] }
      due = scope.where(due_date: today)
      source('Metas e gastos do mês', dashboard_invoices_path(month: today.month, year: today.year))
      { month: today.strftime('%Y-%m'), spent: month_scope.sum(:total), invoices: month_scope.count,
        due_today_count: due.count, due_today_amount: due.sum(:total),
        goals: array_page(entries, {}), exceeded_goals: entries.count { |entry| entry[:exceeded] },
        note: 'Saldo por meta = meta menos os lançamentos nas categorias correspondentes. Saldo negativo indica excesso. Metas podem compartilhar categorias: não some os saldos como orçamento único. Sem meta cadastrada não há saldo estimável. Vencimento não informa se houve pagamento.' }
    end

    def briefing_fleet(today)
      fleet = fleet_status({ 'date' => today.iso8601 })
      used = Mapa.dias_rodados_por_placa(today.month, today.year)
      unused = Plate.active.where(setor: 'ROTA').order(:placa).reject do |plate|
        PlateUtils.equivalentes(plate.placa).any? { |equivalent| used.key?(equivalent) }
      end
      fleet[:without_recorded_trips_this_month] = array_page(unused.map { |plate| { plate: plate.placa } }, {})
      fleet[:trip_note] = 'Sem mapa de rodagem registrado no mês não significa veículo parado ou indisponível; os mapas podem estar incompletos.'
      return fleet unless fleet[:available]
      attention = fleet_status({ 'date' => today.iso8601, 'status' => 'unavailable' })
      exchanges = fleet_status({ 'date' => today.iso8601, 'status' => 'exchange' })
      fleet.except(:records).merge(unavailable: attention, exchange: exchanges,
        dimensioning: fleet_dimensioning({ 'date' => today.iso8601 }))
    end

    def briefing_consumption
      first, last = closing_range({})
      report = Gasola::TeamReport.new(from: first, to: last)
      below = report.by_driver.select { |entry| entry[:totals][:achieved] == false }
      source('Consumo e metas de combustível', fuel_consumptions_path(from: first, to: last))
      { from: first, to: last, totals: report.totals, emissions: report.emissions,
        complete: report.complete?, updated_at: report.sync&.created_at, below_target_drivers: array_page(below, {}),
        note: 'A média e a meta são ponderadas pelo combustível. Sem dados suficientes, a meta é desconhecida; não significa desempenho zero. O consumo não altera o pagamento da variável.' }
    end

    def briefing_indicators(today, focus)
      routines = Routine.visible_to(@user).where(status: :open).where('period_start <= ? AND period_end >= ?', today, today)
      routines = routines.joins(:routine_template).where(routine_templates: { sector: focus }) unless focus == 'all'
      alerts = []
      expected = filled = below_goal = 0
      routines.includes(:routine_template).find_each do |routine|
        indicators = routine.selected_indicators.includes(:routine_indicator_targets)
        values = routine.routine_values.where(routine_indicator_id: indicators.map(&:id)).group_by(&:routine_indicator_id)
        indicators.each do |indicator|
          dates = routine.reference_dates_for(indicator)
          today_expected = dates.include?(today)
          today_filled = Array(values[indicator.id]).any? { |value| value.reference_date == today && value.value.present? }
          expected += 1 if today_expected
          filled += 1 if today_expected && today_filled
          calculated = Routines::CalculationService.call(routine: routine, indicator: indicator,
            values: values[indicator.id] || [], expected_reference_dates: dates)
          deviation = calculated[:achieved] == false
          below_goal += 1 if deviation
          next unless deviation || (today_expected && !today_filled)
          alerts << { routine_id: routine.id, routine: routine.title.presence || routine.routine_template.name,
            indicator: indicator.name, pending_today: today_expected && !today_filled, deviation: deviation, calculation: calculated }
        end
      end
      alerts.sort_by! { |alert| [alert[:deviation] ? 0 : 1, alert[:routine].to_s, alert[:indicator]] }
      shown = array_page(alerts, {})
      shown[:records].each { |alert| source(alert[:routine], routine_path(alert[:routine_id])) }
      { routines: routines.count, expected_today: expected, filled_today: filled, pending_today: expected - filled,
        below_goal: below_goal, alerts: shown,
        note: 'Indicadores de GEROTs abertos e vigentes. Resultados calculados podem ser parciais; pendência de hoje considera a frequência e as datas previstas, não todos os dias do mês.' }
    end

    def briefing_people(today, focus)
      scope = @access.employees.active
      sector = { 'du' => 'du', 'warehouse' => 'az' }[focus]
      scope = scope.in_current_or_last_sector(sector) if sector
      roles = EmployeeRole.for_directory.where(employee_id: scope.select(:id), sector: sector || @access.employee_sectors)
      started = roles.where(starts_on: today)
      pending = roles.where(pending_start: true)
      source('Colaboradores', employees_path(employee_sector: sector))
      { active: scope.count, by_role: roles.group(:cargo).count, by_sector: roles.group(:sector).count,
        role_starts_today: started.count, awaiting_start: pending.count,
        note: 'Cadastro e funções vigentes; não representa presença no trabalho. Consulte a escala para folgas e férias.' }
    end
  end
end
