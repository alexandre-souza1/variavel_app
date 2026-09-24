require "bigdecimal"

module Prolog
  class InspectionDivergences
    GROOVES = {
      "measuredInnerTreadDepth" => "Interno",
      "measuredMiddleInnerTreadDepth" => "Central interno",
      "measuredMiddleOuterTreadDepth" => "Central externo",
      "measuredOuterTreadDepth" => "Externo"
    }.freeze
    LOW_LIMIT = BigDecimal("0.50")
    MEDIUM_LIMIT = BigDecimal("2.00")
    SEVERITIES = { "low" => "Divergência baixa", "medium" => "Divergência média", "high" => "Divergência alta" }.freeze
    attr_reader :rows, :without_previous, :inspection_count

    def initialize(inspections, start_time:, end_time:)
      @rows, @without_previous = [], 0
      records = inspections.uniq { |row| [row["source"], row.fetch("id")] }
      @inspection_count = records.count { |r| timestamp(r).between?(start_time, end_time) }
      readings = records.flat_map do |record|
        measures = record["inspectionMeasures"]
        raise InspectionsClient::Error, "Formato das medidas não reconhecido na Prolog." unless measures.is_a?(Array)
        measures.map { |measure| { time: timestamp(record), record: record, measure: measure } }
      end
      readings.group_by { |r| r[:measure].values_at("tireId", "tireLifeCycleAtInspection") }.each do |key, history|
        next if key.any?(&:nil?)
        GROOVES.each do |field, label|
          previous = nil
          history.sort_by { |r| r[:time] }.chunk { |r| r[:time] }.each do |_time, simultaneous|
            # Conflicting simultaneous readings do not define a reliable order.
            if simultaneous.size > 1
              previous = nil
              next
            end
            current = simultaneous.first
            depth = decimal(current[:measure][field])
            next unless depth
            current = current.merge(depth: depth)
            if current[:time].between?(start_time, end_time)
              if previous
                delta = depth - previous[:depth]
                if delta.positive?
                  @rows << { tire_id: key.first, serial: current[:measure]["tireSerialNumber"], life: key.last,
                             groove: label, previous: previous, current: current, delta: delta,
                             severity: delta <= LOW_LIMIT ? "low" : (delta <= MEDIUM_LIMIT ? "medium" : "high") }
                end
              else
                @without_previous += 1
              end
            end
            previous = current
          end
        end
      end
      @rows.sort_by! { |r| [-r[:delta], -r[:current][:time].to_i] }
    end

    private

    def timestamp(record)
      Time.iso8601(record.fetch("submittedAt"))
    end

    def decimal(value)
      return if value.nil?
      number = BigDecimal(value.to_s, exception: false)
      # Prolog serializes binary floats; measurements are displayed in hundredths of a mm.
      number.round(2) if number&.finite? && number >= 0
    end
  end
end
