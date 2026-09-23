module Gasola
  class ConsumptionReport
    attr_reader :from, :to, :records, :sync

    def initialize(registration:, from:, to:)
      @from, @to = from, to
      @records = registration.present? ? GasolaSupply.consumption.where(registration: registration.to_s.strip,
        concluded_at: from.in_time_zone...to.next_day.in_time_zone).order(:concluded_at).to_a : []
      @sync = GasolaSyncRun.where('from_at <= ? AND to_at > ?', from.in_time_zone,
        from.in_time_zone).order(created_at: :desc).first
    end

    def complete?
      return false unless sync
      required_end = to.next_day.in_time_zone
      required_end = 2.hours.ago if required_end > Time.current
      sync.to_at >= required_end
    end

    def totals(rows = records)
      self.class.summarize(rows)
    end

    def self.summarize(rows)
      valid = rows.select(&:valid_consumption?)
      liters = valid.sum { |row| row.liters }
      distance = valid.sum { |row| row.distance }
      average = liters.positive? ? distance / liters : nil
      goal = if valid.any? && valid.all? { |row| row.goal&.positive? }
        valid.sum { |row| row.goal * row.liters } / liters
      end
      { count: rows.size, excluded: rows.size - valid.size, liters: liters, distance: distance,
        average: average, goal: goal, achieved: goal && average >= goal }
    end

    def by_plate
      records.group_by(&:plate).sort_by { |plate, _| plate.to_s }.map { |plate, rows| [plate, totals(rows)] }
    end
  end
end
