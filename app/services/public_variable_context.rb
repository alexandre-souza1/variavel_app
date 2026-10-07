require "bigdecimal"

class PublicVariableContext
  DOCUMENT_SEARCH_STOPWORDS = %w[
    a ao aos as com da das de do dos e em entre essa esse estas estes eu existe
    há isso me meu minha na nas no nos onde para por que qual quero vejo ver
  ].freeze

  def initialize(identity, question: nil, selected_period: nil)
    @identity = identity
    @record = identity.record
    @question = question.to_s
    @selected_period = selected_period
  end

  def call
    data = case @identity.profile
           when "colaborador" then combined_context
           when "motorista" then employee_record ? career_context : du_context(Mapa.where(matric_motorista: @record.promax))
           when "ajudante" then employee_record ? career_context : du_context(ajudante_mapas)
           when "operador" then operator_context
           when "az_ajudante" then az_helper_context
           else {}
           end

    {
      profile: @identity.label,
      name: @identity.name,
      registration: @identity.registration,
      unit: {
        dream: "Ser o melhor DPO da SAZ, com o time motivado, seguro, produtivo e cliente satisfeito."
      },
      documents: document_context,
      fuel_consumption: fuel_consumption_context,
      time_off: TimeOff::PersonalSchedule.new(person: @record).call,
      people_cycle_current_year: Date.current.year,
      people_cycle_feedbacks: PeopleCycleFeedback.for_identity(@identity).map { |feedback| { cycle: feedback.cycle, stage: feedback.stage, response: feedback.response } },
      period_note: "Os valores são calculados apenas com os dados disponíveis no sistema.",
      data: data
    }
  end

  private

  def fuel_consumption_context
    employee = employee_record
    eligible = employee ? employee.employee_roles.du.where(cargo: %w[motorista van]).exists? : @identity.profile == 'motorista'
    return unless eligible

    current = closing_month_for(Date.current).beginning_of_month
    selected = consumption_selected_month
    registration = employee ? employee.matricula : @identity.registration
    dates = GasolaSupply.consumption.where(registration: employee ? employee.registration_aliases : [registration.to_s.strip])
      .where('concluded_at >= ?', 2.years.ago).pluck(:concluded_at)
    months = (dates.map { |date| closing_month_for(date.in_time_zone.to_date).beginning_of_month } +
      [current, current.prev_month, selected]).compact.uniq.sort
    monthly = months.to_h do |month|
      to = month.change(day: 20)
      report = Gasola::ConsumptionReport.new(registration: registration, employee: employee, from: to.prev_month.change(day: 21), to: to)
      totals = report.totals
      [month.strftime('%Y-%m'), {
        from: report.from.iso8601, to: report.to.iso8601,
        average_km_per_liter: totals[:average]&.round(2)&.to_f,
        goal_km_per_liter: totals[:goal]&.round(2)&.to_f,
        achieved: totals[:achieved], refuelings: totals[:count],
        liters: number(totals[:liters]), distance_km: number(totals[:distance]),
        excluded_refuelings: totals[:excluded], complete: report.complete?,
        updated_at: report.sync&.created_at&.iso8601,
        by_plate: report.by_plate.map { |plate, values| {
          plate: plate, average_km_per_liter: values[:average]&.round(2)&.to_f,
          goal_km_per_liter: values[:goal]&.round(2)&.to_f, achieved: values[:achieved]
        } }
      }]
    end
    {
      source: 'Gasola', current_period: current.strftime('%Y-%m'),
      selected_period: selected&.strftime('%Y-%m'), monthly: monthly,
      period_definition: 'Dia 21 do mês anterior ao dia 20 do mês indicado.',
      calculation: 'Média = quilômetros totais / litros totais. Meta ponderada pelos litros. ARLA e registros sem distância ou litros positivos ficam fora.',
      economical_driving_lup: Rails.application.routes.url_helpers.open_download_path(232)
    }
  end

  def consumption_selected_month
    value = @selected_period.to_s
    return unless value.match?(/\A[0-9]{4}-(0[1-9]|1[0-2])\z/)

    Date.strptime(value, '%Y-%m').beginning_of_month
  rescue Date::Error
    nil
  end

  def employee_record
    @record.is_a?(Employee) ? @record : (@record.respond_to?(:employee) ? @record.employee : nil)
  end

  def career_context
    employee = employee_record
    report = EmployeeVariableReport.new(employee, from: 2.years.ago.to_date)
    monthly = report.maps.group_by { |mapa| closing_month_for(mapa.data_formatada).strftime('%Y-%m') }.sort.to_h do |month, records|
      period = EmployeeVariableReport.new(employee, maps: records)
      [month, money_totals(period.totals).merge(by_role: period.groups.transform_values { |totals| money_totals(totals) }, source: 'prévia')]
    end
    employee.variable_closings.where(sector: 'du').order(:revision).each do |closing|
      month = format('%04d-%02d', closing.year, closing.month)
      totals = closing.result.fetch('totals').symbolize_keys.transform_values { |value| value.to_d }
      groups = closing.result.fetch('groups').transform_values { |group| money_totals(group.symbolize_keys.transform_values { |value| value.to_d }) }
      monthly[month] = money_totals(totals).merge(by_role: groups, source: closing.legacy_baseline? ? 'referência legada, não comprova pagamento' : 'fechamento registrado', revision: closing.revision)
    end
    {
      period_definition: 'Fechamento do dia 21 do mês anterior ao dia 20 do mês informado.',
      current_period: closing_month_for(Date.current).strftime('%Y-%m'), monthly: monthly.sort.to_h,
      issues: report.issues,
      sector: 'du', roles: employee.employee_roles.du.map { |role| { cargo: role.label, inicio: role.starts_on, fim: role.ends_on } },
      rules: { devolution_target: 'Até 3% de devolução e pelo menos 15 mapas, apurados separadamente por cargo. Van também recebe bônus.',
        note: 'Van recebe caixas e entregas nos mapas marcados como recarga, sem remuneração de recarga. O cargo e as tarifas respeitam a data do mapa.' }
    }
  end

  def du_context(scope)
    mapas = scope.to_a.filter_map { |mapa| [mapa.data_formatada, mapa] if mapa.data_formatada }.select { |date, _| date >= 2.years.ago.to_date }
    service = MapaRemuneracaoService.new(@identity.profile == "motorista" ? "motorista" : "ajudante")

    monthly = mapas.group_by { |date, _| closing_month_for(date).strftime("%Y-%m") }.sort.to_h do |month, entries|
      records = entries.map(&:last)
      totals = service.totals(records)
      [month, money_totals(totals).merge(days: entries.map(&:first).uniq.size)]
    end

    daily = mapas.group_by(&:first).sort.last(120).to_h do |date, entries|
      totals = service.totals(entries.map(&:last))
      [date.iso8601, money_totals(totals)]
    end

    {
      period_definition: "Cada mês representa o fechamento do dia 21 do mês anterior ao dia 20 do mês informado. Exemplo: 2026-08 = 21/07/2026 a 20/08/2026.",
      current_period: closing_month_for(Date.current).strftime("%Y-%m"),
      monthly: monthly,
      recent_daily: daily,
      rules: {
        devolution_target: "Até 3% de devolução e pelo menos 15 mapas podem gerar o bônus configurado.",
        note: "O bônus e os valores dependem dos parâmetros vigentes no sistema."
      }
    }
  end

  def combined_context
    employee = employee_record
    du = employee.employee_roles.du.exists? || employee.variable_closings.where(sector: 'du').exists? ? career_context : nil
    az = employee.employee_roles.az.exists? || employee.variable_closings.where(sector: 'az').exists? ? az_context : nil
    return du if du && !az
    return az if az && !du
    { sectors: { du: du, az: az }, current_sector: employee.role_on(Date.current)&.sector,
      period_definition: 'DU fecha de 21 a 20; AZ de 19 a 18. Os períodos são apresentados separadamente.' }
  end

  def operator_context = az_context
  def az_helper_context = az_context

  def az_context
    person = employee_record || @record
    from = 2.years.ago.to_date
    report = AzVariableReport.new(person: person, from: from, to: Date.current)
    months = report.daily.group_by { |day| az_closing_month_for(day[:date]).strftime('%Y-%m') }
    monthly = months.sort.to_h do |key, days|
      anchor = Date.strptime(key, '%Y-%m')
      saved = AzVariableReport.for_period(person: person, from: anchor.prev_month.change(day: 19), to: anchor.change(day: 18))
      values = AzVariableReport::COMPONENTS.to_h { |name| [name, number(saved.component(name))] }
      values.merge!(points: number(saved.quantity(:points)), ondemand_quantity: number(saved.quantity(:ondemand_quantity)), total: number(saved.total))
      [key, values]
    end
    if employee_record
      employee_record.variable_closings.where(sector: 'az').order(:revision).each do |closing|
        snapshot = closing.result
        monthly[format('%04d-%02d', closing.year, closing.month)] = snapshot.fetch('components').symbolize_keys.transform_values { |value| number(value) }
          .merge(total: number(snapshot['total']), source: 'fechamento registrado', revision: closing.revision)
      end
    end
    role = employee_record&.role_on(Date.current)
    turno = role&.az? ? role.turno : @record.try(:turno)
    {
      period_definition: 'Cada mês representa o fechamento do dia 19 do mês anterior ao dia 18 do mês informado.',
      current_period: az_closing_month_for(Date.current).strftime('%Y-%m'), monthly: monthly.sort.to_h,
      sector: 'az', roles: employee_record&.employee_roles&.az&.map { |role| { cargo: role.label, turno: role.shift_label, inicio: role.starts_on, fim: role.ends_on } },
      shift: { code: turno, label: EmployeeRole::TURNOS.key(turno) }, issues: report.issues,
      rules: { efc: 'Ajudantes A/B/C recebem R$ 5 por dia de meta EFC, exceto domingos; suprimento é do turno A e remonte do turno B.' }
    }
  end

  def ajudante_mapas
    Mapa.where(matric_ajudante: @record.promax).or(Mapa.where(matric_ajudante_2: @record.promax))
  end

  def document_context
    keywords = normalized_keywords
    return [] if keywords.empty?

    Download
      .where(category: "PADRÃO")
      .to_a
      .filter_map do |download|
        searchable_text = normalize_text([download.title, download.description, download.sector].compact.join(" "))
        matches = keywords.count { |keyword| searchable_text.include?(keyword) }
        next if matches.zero?

        {
          title: download.title,
          description: download.description,
          category: download.category,
          sector: download.sector,
          link: Rails.application.routes.url_helpers.open_download_path(download)
        }.tap { |document| document[:relevance] = matches }
      end
      .sort_by { |document| -document[:relevance] }
      .first(8)
      .map { |document| document.except(:relevance) }
  end

  def normalized_keywords
    normalize_text(@question)
      .split
      .reject { |word| word.length < 3 || DOCUMENT_SEARCH_STOPWORDS.include?(word) }
      .uniq
  end

  def normalize_text(value)
    value.to_s
      .unicode_normalize(:nfkd)
      .encode("ASCII", invalid: :replace, undef: :replace, replace: "")
      .downcase
      .gsub(/[^a-z0-9]+/, " ")
      .strip
  end

  def closing_month_for(date)
    date.day >= 21 ? date.next_month : date
  end

  def az_closing_month_for(date)
    date.day >= 19 ? date.next_month : date
  end

  def money_totals(totals)
    {
      total: number(totals[:valor_total]),
      boxes: number(totals[:valor_caixas]),
      pdvs: number(totals[:valor_pdvs]),
      refills: number(totals[:valor_recargas]),
      returns: number(totals[:devolucoes]),
      return_percentage: number(totals[:percentual_devolucao] * 100),
      bonus: number(totals[:bonus_devolucao]),
      maps: totals[:quantidade_mapas]
    }
  end

  def decimal(value)
    value.present? ? BigDecimal(value.to_s) : BigDecimal("0")
  end

  def number(value)
    value.to_d.to_f.round(2)
  end

  def normalize(value)
    value.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "").downcase.gsub(/[^a-z0-9]+/, " ").strip
  end
end
