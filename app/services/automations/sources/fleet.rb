module Automations
  module Sources
    class Fleet
      STATUSES = { "unavailable" => "Indisponíveis", "available" => "Na disponibilidade", "exchange" => "No depósito", "special_route" => "Em rota especial" }.freeze

      def self.validate!(rule)
        Configuration.check_keys!(rule.filters, %w[status])
        raise Invalid, "Escolha a situação dos veículos." unless STATUSES.key?(rule.filters["status"])
        raise Invalid, "Disponibilidade consulta um retrato do dia: escolha Hoje ou Ontem." unless rule.period.in?(%w[today yesterday])
      end

      def self.call(rule, period:, now:)
        availability = FleetAvailability.find_by(date: period.anchor)
        count = availability ? availability.fleet_availability_items.where(status: rule.filters["status"]).count : 0
        { value: count.to_d, count: count, available: availability.present?,
          note: "Quantidade de veículos na disponibilidade da data escolhida." }
      end
    end
  end
end
