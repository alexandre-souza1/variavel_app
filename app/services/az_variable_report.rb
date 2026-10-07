class AzVariableReport
  LEGACY_ROLE = Struct.new(:cargo, :turno) do
    def az? = true
  end
  COMPONENTS = %i[tma efficiency wms ondemand point_value refugo efc suprimento remonte].freeze
  attr_reader :person, :employee, :from, :to, :maps, :tasks, :points, :refugo_tasks, :activities, :daily, :issues

  def self.for_period(person:, from:, to:)
    employee = person.is_a?(Employee) ? person : person.try(:employee)
    closing = if employee && from.day == 19 && to.day == 18 && from == to.prev_month.change(day: 19)
      employee.variable_closings.where(sector: 'az', year: to.year, month: to.month).order(revision: :desc).first
    end
    new(person: person, from: from, to: to, snapshot: closing&.result)
  end

  def initialize(person:, from:, to:, snapshot: nil)
    @person, @from, @to = person, from, to
    @employee = person.is_a?(Employee) ? person : person.try(:employee)
    @issues = []
    if snapshot
      @saved_rates = snapshot.fetch('rates', {}).deep_symbolize_keys
      @snapshot_roles = snapshot.fetch('roles', []).map { |attrs| EmployeeRole.new(attrs) }
      @operator_rates = snapshot.dig('rates', 'operador')&.transform_values(&:to_d)
      @daily = snapshot.fetch('daily').map do |entry|
        row = entry.symbolize_keys
        row[:date] = Date.iso8601(row[:date].to_s)
        (COMPONENTS + %i[total_value points ondemand_quantity]).each { |key| row[key] = row[key].to_d }
        row
      end
      sources = snapshot.fetch('sources')
      { maps: AzMapa, tasks: WmsTask, points: AzRvPoint, refugo_tasks: AzRvTask, activities: AzRvOnDemandActivity }.each do |name, model|
        key = name == :refugo_tasks ? 'refugo' : name.to_s
        instance_variable_set("@#{name}", sources.fetch(key, []).map { |attrs| model.new(attrs) })
      end
      return
    end
    @maps = AzMapa.where(data: from..to).order(:data).to_a
    operator_ids = employee ? employee.operators.pluck(:id) : (person.is_a?(Operator) ? [person.id] : [])
    @tasks = WmsTask.where(employee_id: employee&.id).where.not(employee_id: nil)
      .or(WmsTask.where(operator_id: operator_ids)).where(started_at: from.beginning_of_day..to.end_of_day).order(:started_at).to_a
    @points = AzRvPoint.for_person(person).between(from, to).order(:reference_date).to_a
    @refugo_tasks = AzRvTask.for_person(person).between(from, to).where(task_type: 'Blitz Refugo').order(:associated_at).to_a
    @activities = AzRvOnDemandActivity.for_person(person).between(from, to).order(:created_at_source).to_a
    calculate
  end

  def role_on(date)
    return @snapshot_roles.find { |role| role.covers?(date) } if @snapshot_roles
    return if employee&.retired_at && date > employee.retired_at
    return employee.role_on(date) if employee
    LEGACY_ROLE.new(person.is_a?(Operator) ? 'operador' : 'ajudante', person.turno)
  end

  def total = daily.sum(BigDecimal('0')) { |day| day[:total_value] }
  def component(name) = daily.sum(BigDecimal('0')) { |day| day.fetch(name, 0).to_d }
  def quantity(name) = daily.sum { |day| day.fetch(name, 0) }
  def helper_daily = daily.select { |day| day[:cargo] == 'ajudante' }
  def operator_daily = daily.select { |day| day[:cargo] == 'operador' }
  def rate(name) = operator_rates.fetch(name)

  def point_value(point)
    return point.reported_value.to_d if point.reported_value.to_d.positive?
    point.total_points.to_d * (@saved_rates&.fetch(:montagem, nil) || AzRvPoint::POINT_RATE).to_d
  end

  def activity_value(activity)
    return BigDecimal('0') unless activity.rv_category
    rate = @saved_rates&.dig(:activities, activity.rv_category) || AzRvOnDemandActivity::RV_RATES.fetch(activity.rv_category)
    rate.to_d * activity.rv_quantity
  end

  def map_value(map)
    role = role_on(map.data)
    return BigDecimal('0') unless role&.az? && role.cargo == 'operador' && map.turno.include?(role.turno) && map.meta_remunerada?
    return rate('valor_tma') if map.tipo == 'tempo_atendimento'
    efficiency = role.turno == 1 ? 'eficiencia_descarga' : 'eficiencia_carregamento'
    map.tipo == efficiency ? rate('valor_efc') : BigDecimal('0')
  end

  def snapshot
    {
      employee: (employee || person).attributes.slice('id', 'nome', 'matricula', 'cpf'), sector: 'az',
      from: from, to: to, total: total, components: COMPONENTS.to_h { |name| [name, component(name)] },
      daily: daily, roles: employee&.employee_roles&.az&.during(from, to)&.map(&:attributes) || [],
      sources: { maps: maps.map(&:attributes), tasks: tasks.map(&:attributes), points: points.map(&:attributes),
        refugo: refugo_tasks.map(&:attributes), activities: activities.map(&:attributes) },
      rates: { operador: operator_rates, efc: AzHelperEfcService::DAILY_VALUE,
        suprimento: AzHelperSuprimentoService::DAILY_VALUE, remonte: AzHelperRemonteService::PALETTE_RATE,
        refugo: BigDecimal('1.10'), montagem: AzRvPoint::POINT_RATE, activities: AzRvOnDemandActivity::RV_RATES },
      issues: issues, rule: 'AZ: fechamento 19 a 18; cargo e turno respeitam a data da operação.'
    }
  end

  def validate!
    raise EmployeeRole::HistoryError, issues.join(' ') if issues.any?
  end

  private

  def operator_rates
    @operator_rates ||= %w[valor_tma valor_efc tarefa_wms].to_h do |name|
      [name, (ParametroCalculo.valor_para(categoria: 'operador', nome: name) || 0).to_d]
    end
  end

  def calculate
    efc = AzHelperEfcService.new(start_date: from, end_date: to).daily_values
    suprimento = AzHelperSuprimentoService.new(start_date: from, end_date: to).daily_values
    remonte = AzHelperRemonteService.new(start_date: from, end_date: to).daily_values
    by_date = maps.group_by(&:data)
    task_days = tasks.group_by { |task| task.started_at.in_time_zone.to_date }
    point_days = points.group_by(&:reference_date)
    refugo_days = refugo_tasks.group_by { |task| task.associated_at.in_time_zone.to_date }
    activity_days = activities.group_by { |activity| activity.created_at_source.in_time_zone.to_date }
    @daily = (from..to).filter_map do |date|
      role = role_on(date)
      next unless role&.az?
      unless EmployeeRole::TURNOS.value?(role.turno)
        issues << "#{date}: turno AZ não informado; revise o histórico do colaborador."
        next
      end
      row = COMPONENTS.index_with { BigDecimal('0') }.merge(date: date, cargo: role.cargo, turno: role.turno,
        points: BigDecimal('0'), refugo_count: 0, ondemand_quantity: BigDecimal('0'), wms_count: 0,
        tma_count: 0, efficiency_count: 0, efc_day: false, suprimento_day: false)
      if role.cargo == 'operador'
        indicators = Array(by_date[date]).select { |map| map.turno.include?(role.turno) && map.meta_remunerada? }
        row[:tma_count] = indicators.count { |map| map.tipo == 'tempo_atendimento' }
        efficiency = role.turno == 1 ? 'eficiencia_descarga' : 'eficiencia_carregamento'
        row[:efficiency_count] = indicators.count { |map| map.tipo == efficiency }
        row[:wms_count] = Array(task_days[date]).count(&:remunerated?)
        row[:tma] = row[:tma_count] * operator_rates['valor_tma']
        row[:efficiency] = row[:efficiency_count] * operator_rates['valor_efc']
        row[:wms] = row[:wms_count] * operator_rates['tarefa_wms']
        operational = Array(activity_days[date]).select { |activity| activity.rv_category == :ondemand_operacional }
        row[:ondemand_quantity] = operational.sum(BigDecimal('0'), &:rv_quantity)
        row[:ondemand] = row[:ondemand_quantity] * AzOperatorOnDemandService::RATE
      else
        row[:points] = Array(point_days[date]).sum(BigDecimal('0'), &:total_points)
        row[:point_value] = Array(point_days[date]).sum(BigDecimal('0'), &:montagem_value)
        row[:refugo_count] = Array(refugo_days[date]).size
        row[:refugo] = row[:refugo_count] * BigDecimal('1.10')
        row[:ondemand_quantity] = Array(activity_days[date]).sum(BigDecimal('0'), &:rv_quantity)
        row[:ondemand] = Array(activity_days[date]).sum(BigDecimal('0'), &:rv_total_amount)
        row[:efc] = efc.fetch(date, BigDecimal('0'))
        row[:suprimento] = role.turno == 0 ? suprimento.fetch(date, BigDecimal('0')) : BigDecimal('0')
        row[:remonte] = role.turno == 1 ? remonte.fetch(date, BigDecimal('0')) : BigDecimal('0')
        row[:efc_day] = efc.key?(date)
        row[:suprimento_day] = role.turno == 0 && suprimento.key?(date)
      end
      row.merge(total_value: COMPONENTS.sum(BigDecimal('0')) { |name| row[name] })
    end
    @tasks = tasks.select { |task| role_on(task.started_at.in_time_zone.to_date)&.then { |role| role.az? && role.cargo == 'operador' } }
    @points = points.select { |point| helper_on?(point.reference_date) }
    @refugo_tasks = refugo_tasks.select { |task| helper_on?(task.associated_at.in_time_zone.to_date) }
    @activities = activities.select { |activity| role_on(activity.created_at_source.in_time_zone.to_date)&.az? }
  end

  def helper_on?(date)
    role = role_on(date)
    role&.az? && role.cargo == 'ajudante'
  end
end
