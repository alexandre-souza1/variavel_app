require "bigdecimal"

module Prolog
  class PressureHistory
    REFERENCE_RECOMMENDED = BigDecimal("115")
    REFERENCE_MINIMUM = BigDecimal("100")

    attr_reader :rows, :unusable_count

    def initialize(inspections, start_time:, end_time:, reference_date: Date.current)
      @rows, @unusable_count = [], 0
      readings = inspections.uniq { |r| [r["source"], r.fetch("id")] }.flat_map do |record|
        measures = record["inspectionMeasures"]
        raise InspectionsClient::Error, "Formato das medidas não reconhecido na Prolog." unless measures.is_a?(Array)
        measures.map do |measure|
          pressure = number(measure["measuredPressure"])
          recommended = number(measure["recommendedPressure"])
          time = Time.iso8601(record.fetch("submittedAt"))
          valid = pressure && recommended && recommended.positive?
          @unusable_count += 1 if !valid && time.between?(start_time, end_time)
          { record: record, measure: measure, time: time, pressure: pressure, recommended: recommended,
            minimum: valid ? recommended * REFERENCE_MINIMUM / REFERENCE_RECOMMENDED : nil,
            valid: valid, low: valid && pressure * REFERENCE_RECOMMENDED < recommended * REFERENCE_MINIMUM }
        end
      end
      readings.group_by { |r| r[:measure].values_at("tireId", "tireLifeCycleAtInspection") }.each do |key, history|
        next if key.any?(&:nil?)
        ordered = history.select { |r| r[:time] <= end_time }.sort_by { |r| r[:time] }
        times = ordered.group_by { |r| r[:time] }
        streak = 0
        ordered.each_with_index do |current, index|
          ambiguous = times[current[:time]].size > 1
          streak = current[:low] && !ambiguous ? streak + 1 : 0
          next unless current[:low] && current[:time].between?(start_time, end_time)
          following = ordered[index + 1]
          status = if ambiguous || (following && (times[following[:time]].size > 1 || !following[:valid]))
            "unknown"
          elsif following.nil?
            if end_time.in_time_zone.to_date < reference_date.beginning_of_month
              "pending"
            elsif current[:time].in_time_zone.to_date >= reference_date.beginning_of_month
              "current_low"
            else
              "awaiting_month"
            end
          elsif following[:low]
            "persisted"
          else
            "normalized"
          end
          @rows << { tire_id: key.first, serial: current[:measure]["tireSerialNumber"], life: key.last,
                     current: current, following: following, status: status, streak: streak,
                     deficit: current[:recommended] - current[:pressure] }
        end
      end
      @rows.sort_by! { |r| [-r[:current][:time].to_i, -r[:deficit]] }
    end

    private

    def number(value)
      return if value.nil?
      n = BigDecimal(value.to_s, exception: false)
      n.round(2) if n&.finite? && n >= 0
    end
  end
end
