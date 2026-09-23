class AzDashboardService
  attr_reader :operators, :helpers, :indicators, :daily

  def initialize(start_date:, end_date:, turno: nil)
    @start_date, @end_date, @turno = start_date, end_date, turno
  end

  def call
    maps = AzMapa.considerados_na_variavel.where(data: @start_date..@end_date)
    maps = maps.where("? = ANY(turno)", @turno) unless @turno.nil?
    maps = maps.to_a
    @indicators = AzMapa.tipos.keys.map do |type|
      records = maps.select { |map| map.tipo == type }
      { type: type, count: records.size, achieved: records.count(&:atingiu_meta?) }
    end
    @daily = maps.group_by(&:data).sort.to_h.transform_values { |records| records.count(&:atingiu_meta?) }
    @operators = operator_ranking(maps)
    @helpers = helper_ranking
    self
  end

  private

  def people(model)
    scope = model.all
    scope = scope.where(turno: @turno) unless @turno.nil?
    scope.where("active = TRUE OR retired_at >= ?", @start_date)
  end

  def rate(name)
    (ParametroCalculo.valor_para(categoria: "operador", nome: name) || 0).to_d
  end

  def operator_ranking(maps)
    employees = people(Operator).to_a
    tasks = WmsTask.where(operator_id: employees.map(&:id))
                   .where(started_at: @start_date.beginning_of_day..@end_date.end_of_day).group_by(&:operator_id)
    tma_rate, efficiency_rate, wms_rate = rate("valor_tma"), rate("valor_efc"), rate("tarefa_wms")
    employees.map do |person|
      records = maps.select { |map| map.turno.include?(person.turno) && map.meta_remunerada? }
      efficiency = person.turno == 1 ? "eficiencia_descarga" : "eficiencia_carregamento"
      tma = records.count { |map| map.tipo == "tempo_atendimento" }
      ef = records.count { |map| map.tipo == efficiency }
      wms = Array(tasks[person.id]).count { |task| task.duration.to_f * 60 >= 10 }
      { person: person, tma: tma, efficiency: ef, wms: wms,
        tma_value: tma * tma_rate, efficiency_value: ef * efficiency_rate, wms_value: wms * wms_rate,
        total: tma * tma_rate + ef * efficiency_rate + wms * wms_rate }
    end.sort_by { |row| [-row[:total], row[:person].nome.to_s] }
  end

  def employee_key(name)
    name.to_s.unicode_normalize(:nfkd).encode("ASCII", invalid: :replace, undef: :replace, replace: "")
        .downcase.gsub(/[^a-z0-9]+/, " ").strip
  end

  def helper_ranking
    efc = AzHelperEfcService.new(start_date: @start_date, end_date: @end_date)
    suprimento = AzHelperSuprimentoService.new(start_date: @start_date, end_date: @end_date)
    employees = people(AzAjudante).to_a
    employees.map do |person|
      person_points = AzRvPoint.for_employee(person.nome).between(@start_date, @end_date).to_a
      person_refugo = AzRvTask.for_employee(person.nome).where(task_type: "Blitz Refugo").between(@start_date, @end_date).count
      person_activities = AzRvOnDemandActivity.for_employee(person.nome).between(@start_date, @end_date).to_a
      point_value = person_points.sum(&:montagem_value)
      refugo_value = person_refugo * BigDecimal("1.10")
      activity_value = person_activities.sum(&:rv_total_amount)
      { person: person, points: person_points.sum { |point| point.total_points.to_d },
        point_value: point_value, refugo: person_refugo, refugo_value: refugo_value,
        activities: person_activities.sum(&:rv_quantity), activity_value: activity_value,
        efc_days: efc.daily_values.size, efc_value: efc.total,
        suprimento_days: person.turno.to_i == 0 ? suprimento.daily_values.size : 0,
        suprimento_value: person.turno.to_i == 0 ? suprimento.total : BigDecimal("0"),
        total: point_value + refugo_value + activity_value + efc.total + (person.turno.to_i == 0 ? suprimento.total : 0) }
    end.sort_by { |row| [-row[:total], row[:person].nome.to_s] }
  end
end
