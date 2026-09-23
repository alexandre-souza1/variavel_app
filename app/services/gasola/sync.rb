module Gasola
  class Sync
    def self.default_from(today = Date.current)
      closing = today.day <= 20 ? today : today.next_month
      closing.prev_month(2).change(day: 21).in_time_zone
    end

    def initialize(client: Client.new)
      @client = client
    end

    def call(from: self.class.default_from, to: Time.current)
      raise ArgumentError, 'Intervalo inválido.' unless from < to

      # Serialize imports across hourly processes and manual runs, without holding a DB transaction during HTTP calls.
      GasolaSupply.connection_pool.with_connection do |connection|
        locked = connection.select_value('SELECT pg_try_advisory_lock(739231201)')
        return unless locked
        begin
          rows = []
          cursor = from
          while cursor < to
            boundary = [cursor + 30.days, to].min
            rows.concat(@client.supplies(from: cursor, to: boundary))
            cursor = boundary
          end
          now = Time.current
          attributes = rows.map { |row| attributes_for(row, now) }.index_by { |row| row[:external_id] }.values
          GasolaSupply.transaction do
            GasolaSupply.upsert_all(attributes, unique_by: :external_id) if attributes.any?
            GasolaSyncRun.create!(from_at: from, to_at: to, records_count: attributes.size)
          end
          attributes.size
        ensure
          connection.execute('SELECT pg_advisory_unlock(739231201)')
        end
      end
    end

    private

    def attributes_for(row, now)
      raise Client::Error, 'Abastecimento sem identificador.' if row['id'].blank?
      {
        external_id: row.fetch('id'), registration: row['matricula'].to_s.strip.presence,
        plate: row['placa'], fuel: row['combustivel'], category: row['categoria'], status: row['status'],
        concluded_at: Time.zone.strptime(row.fetch('dataConclusao'), '%d/%m/%Y %H:%M'),
        liters: decimal(row['totalLitros']), distance: decimal(row['kmRodado']), goal: decimal(row['metaKmPorLitro']),
        co2_emission: decimal(row['emissaoCo2']), co2_goal: decimal(row['emissaoCo2Meta']),
        co2_impact: decimal(row['impactoCo2']),
        created_at: now, updated_at: now
      }
    rescue KeyError, ArgumentError, TypeError
      raise Client::Error, 'Abastecimento com data ou valor inválido; sincronização não aplicada.'
    end

    def decimal(value)
      return if value.nil?
      number = BigDecimal(value.to_s)
      raise ArgumentError unless number.finite?
      number
    end
  end
end
