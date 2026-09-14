require "bigdecimal"

class PublicVariableContext
  def initialize(identity)
    @identity = identity
    @record = identity.record
  end

  def call
    data = case @identity.profile
           when "motorista" then du_context(Mapa.where(matric_motorista: @record.promax))
           when "ajudante" then du_context(ajudante_mapas)
           when "operador" then operator_context
           when "az_ajudante" then az_helper_context
           else {}
           end

    {
      profile: @identity.label,
      name: @identity.name,
      registration: @identity.registration,
      period_note: "Os valores são calculados apenas com os dados disponíveis no sistema.",
      data: data
    }
  end

  private

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

  def operator_context
    start_date = 2.years.ago.to_date
    maps = AzMapa.where("? = ANY(turno)", @record.turno).where(data: start_date..Date.current).to_a
    tasks = WmsTask.where(operator_id: @record.id).where(started_at: start_date.beginning_of_day..Time.current).to_a
    tma_value = decimal(ParametroCalculo.valor_para(categoria: "operador", nome: "valor_tma"))
    efficiency_value = decimal(ParametroCalculo.valor_para(categoria: "operador", nome: "valor_efc"))
    wms_value = decimal(ParametroCalculo.valor_para(categoria: "operador", nome: "tarefa_wms"))

    months = (maps.filter_map(&:data) + tasks.filter_map { |task| task.started_at&.to_date }).map { |date| az_closing_month_for(date) }.uniq.sort
    monthly = months.to_h do |month_date|
      month = month_date.strftime("%Y-%m")
      month_start = month_date.prev_month.change(day: 19)
      month_end = month_date.change(day: 18)
      month_maps = maps.select { |mapa| mapa.data.between?(month_start, month_end) }
      month_tasks = tasks.select { |task| task.started_at&.to_date&.between?(month_start, month_end) }
      tma = month_maps.count { |mapa| mapa.tipo == "tempo_atendimento" && mapa.atingiu_meta } * tma_value
      efficiency_type = [0, 2].include?(@record.turno.to_i) ? "eficiencia_carregamento" : "eficiencia_descarga"
      efficiency = month_maps.count { |mapa| mapa.tipo == efficiency_type && mapa.atingiu_meta } * efficiency_value
      wms = month_tasks.sum { |task| task.duration.to_i >= 10 ? wms_value : 0 }
      [month, { tma: number(tma), efficiency: number(efficiency), wms: number(wms), total: number(tma + efficiency + wms) }]
    end

    {
      period_definition: "Cada mês representa o fechamento do dia 19 do mês anterior ao dia 18 do mês informado.",
      current_period: az_closing_month_for(Date.current).strftime("%Y-%m"),
      monthly: monthly,
      shift: { code: @record.turno, label: { 0 => "A", 1 => "B", 2 => "C" }[@record.turno] }
    }
  end

  def az_helper_context
    start_date = 2.years.ago.to_date
    key = normalize(@record.nome)
    points = AzRvPoint.where(employee_key: key).where(reference_date: start_date..Date.current).to_a
    refugo = AzRvTask.where(employee_key: key).between(start_date, Date.current).where(task_type: "Blitz Refugo").to_a
    activities = AzRvOnDemandActivity.where(employee_key: key).between(start_date, Date.current).to_a
    dates = (points.map(&:reference_date) + refugo.filter_map { |item| item.associated_at&.to_date } + activities.filter_map { |item| item.created_at_source&.to_date }).compact.uniq

    months = dates.map { |date| az_closing_month_for(date) }.uniq.sort
    monthly = months.to_h do |month_date|
      month = month_date.strftime("%Y-%m")
      start_month = month_date.prev_month.change(day: 19)
      end_month = month_date.change(day: 18)
      month_points = points.select { |item| item.reference_date.between?(start_month, end_month) }
      month_refugo = refugo.select { |item| item.associated_at&.to_date&.between?(start_month, end_month) }
      month_activities = activities.select { |item| item.created_at_source&.to_date&.between?(start_month, end_month) }
      point_value = month_points.sum(&:montagem_value)
      refugo_value = BigDecimal("1.10") * month_refugo.size
      ondemand_value = month_activities.sum(&:rv_amount)
      [month, { points: number(month_points.sum(&:total_points)), point_value: number(point_value), refugo: number(refugo_value), ondemand: number(ondemand_value), total: number(point_value + refugo_value + ondemand_value) }]
    end

    {
      period_definition: "Ajudantes do armazém usam o período de fechamento do dia 19 ao dia 18.",
      current_period: az_closing_month_for(Date.current).strftime("%Y-%m"),
      monthly: monthly,
      rules: { refugo_value: "Cada Blitz Refugo vale R$ 1,10.", other_values: "Os demais valores seguem as taxas cadastradas no sistema." }
    }
  end

  def ajudante_mapas
    Mapa.where(matric_ajudante: @record.promax).or(Mapa.where(matric_ajudante_2: @record.promax))
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
