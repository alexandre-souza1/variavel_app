class AzDashboardService
  attr_reader :operators, :helpers, :indicators, :daily

  def initialize(start_date:, end_date:, turno: nil)
    @start_date, @end_date, @turno = start_date, end_date, turno
  end

  def call
    maps = AzMapa.where(data: @start_date..@end_date)
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
      records = maps.select { |map| map.turno.include?(person.turno) && map.atingiu_meta? }
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
    employees = people(AzAjudante).to_a
    keys = employees.map { |person| employee_key(person.nome) }
    points = AzRvPoint.where(employee_key: keys).between(@start_date, @end_date).group_by(&:employee_key)
    refugo = AzRvTask.where(employee_key: keys, task_type: "Blitz Refugo").between(@start_date, @end_date).group(:employee_key).count
    activities = AzRvOnDemandActivity.where(employee_key: keys).between(@start_date, @end_date).group_by(&:employee_key)
    employees.map do |person|
      key = employee_key(person.nome)
      person_points = Array(points[key])
      person_activities = Array(activities[key])
      point_value = person_points.sum(&:montagem_value)
      refugo_value = refugo.fetch(key, 0) * BigDecimal("1.10")
      activity_value = person_activities.sum(&:rv_amount)
      { person: person, points: person_points.sum { |point| point.total_points.to_d },
        point_value: point_value, refugo: refugo.fetch(key, 0), refugo_value: refugo_value,
        activities: person_activities.size, activity_value: activity_value,
        total: point_value + refugo_value + activity_value }
    end.sort_by { |row| [-row[:total], row[:person].nome.to_s] }
  end
end
