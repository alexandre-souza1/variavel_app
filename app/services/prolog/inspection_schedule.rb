module Prolog
  class InspectionSchedule
    INTERVAL_DAYS = 30
    WARNING_DAYS = 7
    STATUSES = {
      "overdue" => ["Vencidas", "danger", "bi-exclamation-triangle"],
      "today" => ["Vencem hoje", "danger", "bi-calendar-event"],
      "soon" => ["Vencem em até 7 dias", "warning", "bi-hourglass-split"],
      "missing" => ["Sem histórico", "muted", "bi-question-circle"],
      "ok" => ["Em dia", "success", "bi-check-circle"]
    }.freeze

    attr_reader :rows

    def initialize(plates, inspections, now: Time.current)
      latest = {}
      inspections.each do |record|
        next unless %w[TREAD_DEPTH TREAD_DEPTH_PRESSURE].include?(record["typeMeasurementsCollected"])
        next unless record["source"].nil? || record["source"] == "vehicles"

        time = timestamp(record["submittedAt"])
        next unless time && time <= now

        key = PlateUtils.normalizar(record.dig("vehicle", "licensePlate"))
        next if key.blank?

        latest[key] = { time: time, record: record } if latest[key].nil? || latest[key][:time] < time
      end
      @rows = plates.map do |plate|
        reading = PlateUtils.equivalentes(plate.placa).filter_map { |key| latest[key] }.max_by { |item| item[:time] }
        last_date = reading&.dig(:time)&.in_time_zone&.to_date
        due_date = last_date && last_date + INTERVAL_DAYS
        days_left = due_date && (due_date - now.in_time_zone.to_date).to_i
        status = if days_left.nil? then "missing"
                 elsif days_left.negative? then "overdue"
                 elsif days_left.zero? then "today"
                 elsif days_left <= WARNING_DAYS then "soon"
                 else "ok"
                 end
        { plate: plate, reading: reading, last_date: last_date, due_date: due_date, days_left: days_left, status: status }
      end.sort_by { |row| [STATUSES.keys.index(row[:status]), row[:days_left] || 0, row[:plate].placa] }
    end

    private

    def timestamp(value)
      Time.iso8601(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
