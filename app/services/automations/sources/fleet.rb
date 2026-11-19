module Automations
  module Sources
    class Fleet
      OPERATIONAL_PERCENTAGE = "operational_percentage"
      STATUSES = { "unavailable" => "Indisponíveis", "available" => "Na disponibilidade", "exchange" => "No depósito", "special_route" => "Em rota especial",
        OPERATIONAL_PERCENTAGE => "Disponibilidade operacional total (%)" }.freeze

      def self.validate!(rule)
        Configuration.check_keys!(rule.filters, %w[status])
        raise Invalid, "Escolha a situação dos veículos." unless STATUSES.key?(rule.filters["status"])
        if rule.filters["status"] == OPERATIONAL_PERCENTAGE
          raise Invalid, "A disponibilidade operacional total exige Hoje, Ontem, Mês atual ou Mês anterior." unless rule.period.in?(%w[today yesterday month last_month])
          raise Invalid, "Disponibilidade operacional total exige o cálculo de percentual." unless rule.operation == "percentage"
        else
          raise Invalid, "Disponibilidade por situação consulta um retrato do dia: escolha Hoje ou Ontem." unless rule.period.in?(%w[today yesterday])
          raise Invalid, "Disponibilidade por situação exige contagem." unless rule.operation == "count"
        end
      end

      def self.call(rule, period:, now:)
        return operational_percentage(period) if rule.filters["status"] == OPERATIONAL_PERCENTAGE

        availability = FleetAvailability.find_by(date: period.anchor)
        count = availability ? availability.fleet_availability_items.where(status: rule.filters["status"]).count : 0
        { value: count.to_d, count: count, available: availability.present?,
          note: "Quantidade de veículos na disponibilidade da data escolhida." }
      end

      def self.operational_percentage(period)
        snapshots = FleetAvailability.where(date: period.date_range)
          .includes(fleet_availability_items: :plate).order(:date)
        daily_percentages = snapshots.map do |availability|
          items = availability.fleet_availability_items.select { |item| item.plate.active_on?(availability.date) }
          operational_count = items.count { |item| !item.unavailable? }
          items.empty? ? 0 : (operational_count.to_f / items.size) * 100
        end
        available = daily_percentages.any?
        percentage = available ? (daily_percentages.sum / daily_percentages.size).round : 0
        { value: percentage.to_d, count: daily_percentages.size, available: available,
          note: "Percentual de veículos utilizáveis (disponíveis, em depósito/troca ou em rota especial) sobre as placas ativas em cada retrato. Em período mensal, faz a média dos dias com retrato; dias sem retrato não entram no cálculo." }
      end
    end
  end
end
