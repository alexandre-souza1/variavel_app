module AiAssistant
  module FleetQueries
    private

    def fleet_analysis(args)
      first, last = calendar_range(args)
      observed_until = [last, Date.current].min
      snapshots = FleetAvailability.where(date: first..observed_until)
        .includes(fleet_availability_items: :plate).order(:date).to_a
      reasons = Hash.new(0)
      daily = snapshots.map do |fleet|
        items = fleet.fleet_availability_items.select { |item| item.plate.active_on?(fleet.date) }
        counts = FleetAvailabilityItem.statuses.keys.index_with { |status| items.count { |item| item.status == status } }
        items.select(&:unavailable?).each { |item| reasons[item.reason_label] += 1 }
        { date: fleet.date, counts: counts, fleet_total: items.size, agreed_quantity: fleet.agreed_quantity,
          below_target: counts['available'] < fleet.agreed_quantity,
          shortfall: [fleet.agreed_quantity - counts['available'], 0].max }
      end
      observed_days = [(observed_until - first).to_i + 1, 0].max
      missing_days = observed_days - daily.size
      source('Histórico de disponibilidade da frota', fleet_availabilities_path(date: first.iso8601))
      result = { from: first, to: last, observed_until: observed_days.positive? ? observed_until : nil,
        available: daily.any?, calendar_days: (last - first).to_i + 1, recorded_days: daily.size,
        missing_days: missing_days, future_days: (last - first).to_i + 1 - observed_days,
        partial: last > Date.current || missing_days.positive?, daily: array_page(daily, args),
        basis: 'Média aritmética dos retratos diários cadastrados até hoje, com o mesmo peso por dia. Dias sem registro e dias futuros ficam fora do denominador. Disponíveis significa status available; troca e rotas especiais são separados. Cada retrato considera placas ativas na sua data.',
        note: 'Retratos salvos podem ter sido editados; não representam uma média de todas as alterações ao longo do dia.' }
      return result.merge(message: 'Não há disponibilidade cadastrada no período observado; não é possível calcular uma média.', averages: nil) if daily.empty?

      averages = FleetAvailabilityItem.statuses.keys.index_with do |status|
        (daily.sum { |row| row[:counts][status] }.to_f / daily.size).round(2)
      end
      averages['fleet_total'] = (daily.sum { |row| row[:fleet_total] }.to_f / daily.size).round(2)
      averages['agreed_quantity'] = (daily.sum { |row| row[:agreed_quantity] }.to_f / daily.size).round(2)
      minimum, maximum = daily.map { |row| row[:counts]['available'] }.minmax
      result.merge(averages: averages, days_below_target: daily.count { |row| row[:below_target] },
        shortfall_vehicle_days: daily.sum { |row| row[:shortfall] },
        minimum_available: { count: minimum, dates: daily.select { |row| row[:counts]['available'] == minimum }.pluck(:date) },
        maximum_available: { count: maximum, dates: daily.select { |row| row[:counts]['available'] == maximum }.pluck(:date) },
        unavailable_reasons_vehicle_days: reasons.sort_by { |reason, count| [-count, reason] }.to_h)
    end
  end
end
