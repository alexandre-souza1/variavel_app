class DuDevolutionReport
  attr_reader :ignored_maps_count

  def initialize(maps)
    load_members(maps)
    @ignored_maps_count = 0
    @records = maps.filter_map do |map|
      date = map.data_formatada
      next if recarga?(map, date)

      total = map.pdv_total.to_d
      delivered = map.pdv_real.to_d
      if date.nil? || map.pdv_total.nil? || map.pdv_real.nil? || total <= 0 || delivered < 0 || delivered > total
        @ignored_maps_count += 1
        next
      end
      { map: map, date: date, total: total, delivered: delivered, returned: total - delivered }
    end
  end

  def general
    @general ||= summarize(@records)
  end

  def general_chart_data
    return [] unless general[:percentage]

    [['Entregues', general[:delivered].to_f], ['Devolvidos', general[:returned].to_f]]
  end

  def ranking(profile, limit: 10)
    @rankings ||= {}
    entries = @rankings[profile] ||= begin
      buckets = {}
      @records.each do |record|
        map = record[:map]
        codes = profile == :driver ? [map.matric_motorista] : [map.matric_ajudante, map.matric_ajudante_2]
        people = codes.filter_map { |code| member(code, profile, record[:date], override: map.cargo_override) }.uniq { |person| person[:key] }
        people.each do |person|
          bucket = buckets[person[:key]] ||= { person: person, records: [] }
          bucket[:records] << record
        end
      end
      buckets.values.map { |bucket| summarize(bucket[:records]).merge(person: bucket[:person]) }
        .select { |entry| entry[:returned].positive? }
        .sort_by { |entry| [-entry[:percentage], -entry[:returned], entry[:person][:name], entry[:person][:key]] }
    end
    limit ? entries.first(limit) : entries
  end

  def ranking_chart_data(profile)
    entries = ranking(profile)
    names = entries.group_by { |entry| entry[:person][:name] }
    entries.map do |entry|
      person = entry[:person]
      label = names[person[:name]].many? ? "#{person[:name]} · #{person[:registration]}" : person[:name]
      [label, (entry[:percentage] * 100).to_f]
    end
  end

  def daily_chart_data
    @records.group_by { |record| record[:date] }.sort.to_h do |date, records|
      [date.iso8601, (summarize(records)[:percentage] * 100).to_f]
    end
  end

  def unresolved_members
    @unresolved_members ||= @records.flat_map do |record|
      map = record[:map]
      { driver: [map.matric_motorista], helper: [map.matric_ajudante, map.matric_ajudante_2] }.flat_map do |profile, codes|
        codes.filter_map do |code|
          person = member(code, profile, record[:date], override: map.cargo_override)
          person if person && !person[:key].start_with?('employee-', 'legacy-')
        end
      end
    end.uniq { |person| person[:key] }
  end

  private

  def summarize(records)
    total = records.sum { |record| record[:total] }
    delivered = records.sum { |record| record[:delivered] }
    returned = records.sum { |record| record[:returned] }
    { maps: records.size, total: total, delivered: delivered, returned: returned,
      percentage: total.positive? ? returned / total : nil }
  end

  def load_members(maps)
    codes = maps.flat_map(&:employee_codes).map(&:strip).uniq
    @roles = EmployeeRole.du.includes(:employee).where(promax: codes).group_by(&:promax)
    @legacy = { driver: Driver, helper: Ajudante }.transform_values do |model|
      model.where(employee_id: nil, promax: codes).group_by { |person| person.promax.to_s }
    end
  end

  def recarga?(map, date)
    return false unless map.recarga == 'SIM'
    return map.cargo_override != 'van' if map.cargo_override.present?

    roles = @roles.fetch(map.matric_motorista.to_s.strip, []).select { |role| role.covers?(date) && %w[motorista van].include?(role.cargo) }
    !(roles.one? && roles.first.cargo == 'van')
  end

  def member(code, profile, date, override: nil)
    code = code.to_s.strip
    return if code.blank? || code == '0'

    cargos = profile == :driver ? %w[motorista van] : ['ajudante']
    people = @roles.fetch(code, []).select { |role| (cargos.include?(role.cargo) || override.present?) && role.covers?(date) }.map(&:employee).uniq(&:id)
    return { key: "employee-#{people.first.id}", name: people.first.nome, registration: people.first.matricula } if people.one?
    return { key: "ambiguous-#{profile}-#{code}", name: "Promax #{code} · Cadastro duplicado", registration: code } if people.many?

    legacy = @legacy.fetch(profile).fetch(code, [])
    return { key: "legacy-#{profile}-#{legacy.first.id}", name: legacy.first.nome, registration: legacy.first.matricula.presence || code } if legacy.one?

    name = legacy.many? ? "Promax #{code} · Cadastro duplicado" : "#{profile == :driver ? 'Motorista' : 'Ajudante'} #{code}"
    { key: "code-#{profile}-#{code}", name: name, registration: code }
  end
end
