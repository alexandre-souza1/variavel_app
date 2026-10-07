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
    @operators = ranking(Operator, 'operador')
    @helpers = ranking(AzAjudante, 'ajudante')
    self
  end

  private

  def people(model, cargo)
    roles = EmployeeRole.az.where(cargo: cargo).during(@start_date, @end_date)
    roles = roles.where(turno: @turno) unless @turno.nil?
    saved_ids = []
    if @start_date == @end_date.prev_month.change(day: 19) && @end_date.day == 18
      profile = { sector: 'az', cargo: cargo }
      profile[:turno] = @turno unless @turno.nil?
      saved_ids = VariableClosing.where(sector: 'az', year: @end_date.year, month: @end_date.month)
        .where("result -> 'roles' @> ?", [profile].to_json).distinct.pluck(:employee_id)
    end
    linked = model.where(employee_id: roles.select(:employee_id)).or(model.where(employee_id: saved_ids))
    legacy = model.where(employee_id: nil)
    legacy = legacy.where(turno: @turno) unless @turno.nil?
    linked.or(legacy).where('active = TRUE OR retired_at >= ? OR employee_id IN (?)', @start_date, saved_ids.presence || [-1]).to_a
      .uniq { |person| person.employee_id || "legacy:#{person.id}" }
  end

  def ranking(model, cargo)
    people(model, cargo).map do |person|
      report = AzVariableReport.for_period(person: person, from: @start_date, to: @end_date)
      days = report.daily.select { |day| day[:cargo] == cargo && (@turno.nil? || day[:turno] == @turno) }
      sum = ->(key) { days.sum(BigDecimal('0')) { |day| day.fetch(key, 0).to_d } }
      row = { person: person, total: sum.call(:total_value),
        ondemand_quantity: sum.call(:ondemand_quantity), ondemand_value: sum.call(:ondemand) }
      if cargo == 'operador'
        row.merge(tma: sum.call(:tma_count).to_i, efficiency: sum.call(:efficiency_count).to_i,
          wms: sum.call(:wms_count).to_i, tma_value: sum.call(:tma),
          efficiency_value: sum.call(:efficiency), wms_value: sum.call(:wms))
      else
        row.merge(points: sum.call(:points), point_value: sum.call(:point_value),
          refugo: sum.call(:refugo_count).to_i, refugo_value: sum.call(:refugo),
          activities: sum.call(:ondemand_quantity), activity_value: sum.call(:ondemand),
          efc_days: days.count { |day| day[:efc_day] }, efc_value: sum.call(:efc),
          suprimento_days: days.count { |day| day[:suprimento_day] }, suprimento_value: sum.call(:suprimento),
          remonte_value: sum.call(:remonte), remonte_quantity: sum.call(:remonte) / AzHelperRemonteService::PALETTE_RATE)
      end
    end.sort_by { |row| [-row[:total], row[:person].nome.to_s] }
  end
end
