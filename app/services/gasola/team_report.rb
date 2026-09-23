module Gasola
  class TeamReport
    attr_reader :from, :to, :records, :sync, :drivers, :plates, :fuels

    def initialize(from:, to:, registration: nil, plate: nil, fuel: nil)
      @from, @to = from, to
      scope = GasolaSupply.consumption.where(concluded_at: from.in_time_zone...to.next_day.in_time_zone)
      registrations = scope.distinct.pluck(:registration).compact
      @names = Employee.where(matricula: registrations).group_by(&:matricula).transform_values do |people|
        people.one? ? people.first.nome : 'Cadastro duplicado'
      end
      @drivers = registrations.sort.map { |key| ["#{@names[key] || 'Sem cadastro'} · #{key}", key] }
      @plates = scope.distinct.order(:plate).pluck(:plate).compact
      @fuels = scope.distinct.order(:fuel).pluck(:fuel).compact
      scope = scope.where(registration: registration) if registration.present?
      scope = scope.where(plate: plate) if plate.present?
      scope = scope.where(fuel: fuel) if fuel.present?
      @records = scope.order(concluded_at: :desc, id: :desc).to_a
      @sync = GasolaSyncRun.where('from_at <= ? AND to_at > ?', from.in_time_zone, from.in_time_zone).order(created_at: :desc).first
    end

    def complete?
      required_end = to.next_day.in_time_zone
      required_end = 2.hours.ago if required_end > Time.current
      sync.present? && sync.to_at >= required_end
    end

    def totals(rows = records)
      ConsumptionReport.summarize(rows)
    end

    def emissions(rows = records)
      values = rows.filter_map { |row| row.co2_emission if row.co2_emission && row.co2_emission >= 0 }
      { count: values.size, missing: rows.size - values.size,
        total: values.any? ? values.sum : nil, average: values.any? ? values.sum / values.size : nil }
    end

    def name(registration)
      @names[registration] || (registration.present? ? 'Sem cadastro vinculado' : 'Matrícula não informada')
    end

    def by_driver
      @by_driver ||= records.group_by(&:registration).map do |registration, rows|
        { registration: registration, name: name(registration), plates: rows.map(&:plate).compact.uniq.sort,
          totals: totals(rows), emissions: emissions(rows) }
      end.sort_by { |entry| [entry[:totals][:achieved] == false ? 0 : 1, entry[:name], entry[:registration].to_s] }
    end

    def daily_average
      records.group_by { |row| row.concluded_at.in_time_zone.to_date }.sort.to_h do |date, rows|
        [date.iso8601, totals(rows)[:average]&.to_f]
      end
    end

    def by_plate
      records.group_by(&:plate).sort_by { |plate, _| plate.to_s }.map { |plate, rows| [plate, totals(rows)] }
    end
  end
end
