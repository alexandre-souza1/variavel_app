require "httparty"

module Prolog
  class TiresClient
    include HTTParty

    BASE_URL = "https://prologapp.com/prolog/api/v3/tires".freeze
    DEFAULT_BRANCH_OFFICE_ID = 1834
    PAGE_SIZE = 100
    SPARE_AXLE = 9
    SPARE_POSITION_PREFIXES = %w[ETP ESTEPE SPARE].freeze

    attr_reader :error

    def tires_for_plate(plate)
      equivalents = PlateUtils.equivalentes(plate)
      return [] if equivalents.empty?

      installed_tires.select { |tire| equivalents.include?(PlateUtils.normalizar(tire[:plate])) }
        .sort_by { |tire| [tire[:spare] ? 1 : 0, tire[:smallest_tread_depth] || Float::INFINITY, tire[:position].to_s] }
    end

    def initialize(
      token: ENV["PROLOG_API_TOKEN"].presence,
      branch_office_id: ENV["PROLOG_BRANCH_OFFICE_ID"].presence || DEFAULT_BRANCH_OFFICE_ID,
      http_client: self.class
    )
      @token = token
      @branch_office_id = branch_office_id
      @http_client = http_client
    end

    # Retorna a menor profundidade medida para cada placa instalada.
    # A API pode trazer várias medições para a mesma placa, uma por pneu.
    def tread_depth_by_plate
      grouped_depths = Hash.new { |hash, key| hash[key] = [] }

      operational_tires.each do |tire|
        plate = tire[:plate]
        next if plate.blank? || tire[:smallest_tread_depth].blank?

        PlateUtils.equivalentes(plate).each do |equivalent_plate|
          grouped_depths[equivalent_plate] << tire[:smallest_tread_depth]
        end
      end

      grouped_depths.transform_values(&:min)
    rescue StandardError => e
      Rails.logger.warn("Não foi possível consultar as medidas de pneus no Prolog: #{e.message}")
      {}
    end

    def tire_summary_by_plate
      summaries = Hash.new { |hash, key| hash[key] = { total: 0, operational_count: 0, spare_count: 0, minimum_tread_depth: nil } }

      installed_tires.each do |tire|
        plate = tire[:plate]
        next if plate.blank?

        PlateUtils.equivalentes(plate).each do |equivalent_plate|
          summary = summaries[equivalent_plate]
          summary[:total] += 1

          if tire[:spare]
            summary[:spare_count] += 1
          else
            summary[:operational_count] += 1
            depth = tire[:smallest_tread_depth]
            summary[:minimum_tread_depth] = [summary[:minimum_tread_depth], depth].compact.min
          end
        end
      end

      summaries
    rescue StandardError => e
      Rails.logger.warn("Não foi possível resumir os pneus por placa: #{e.message}")
      {}
    end

    # Retorna um item por pneu instalado no limite de recape ou abaixo dele.
    # `created_at` é a data do registro disponibilizada pela API para o dado.
    def tires_needing_retread(threshold: 3.5)
      operational_tires
        .select { |tire| tire[:smallest_tread_depth].present? && tire[:smallest_tread_depth] <= threshold }
        .sort_by { |tire| [tire[:smallest_tread_depth], tire[:plate].to_s, tire[:fire_number].to_s] }
    rescue StandardError => e
      Rails.logger.warn("Não foi possível consultar as medidas de pneus no Prolog: #{e.message}")
      []
    end

    private

    def installed_tires
      @error = nil
      if @token.blank?
        @error = :not_configured
        return []
      end

      page_number = 0
      tires = []

      loop do
        response = @http_client.get(
          BASE_URL,
          query: {
            branchOfficesId: @branch_office_id,
            tireStatuses: "INSTALLED",
            pageSize: PAGE_SIZE,
            pageNumber: page_number
          },
          headers: { "x-prolog-api-token" => @token },
          timeout: 10
        )

        raise "HTTP #{response.code}" unless response.success?

        payload = response.parsed_response
        Array(payload["content"]).each do |tire|
          installed = tire["installed"] || {}
          spare = spare_tire?(installed)
          tire_data = {
            plate: installed["licensePlate"],
            vehicle_type: installed["vehicleTypeName"],
            fire_number: tire["serialNumber"],
            position: installed["installedPositionName"],
            smallest_tread_depth: valid_depth(tire["smallestTreadDepth"]),
            created_at: tire["createdAt"]
          }
          tire_data[:spare] = true if spare
          tires << tire_data
        end

        break if payload["lastPage"] != false

        page_number += 1
        raise "Paginação incompleta" if page_number >= 100
      end

      tires
    rescue StandardError => e
      @error = :unavailable
      Rails.logger.warn("Não foi possível consultar as medidas de pneus no Prolog: #{e.message}")
      []
    end

    def operational_tires
      installed_tires.reject { |tire| tire[:spare] }
    end

    def valid_depth(value)
      depth = Float(value, exception: false)
      depth if depth&.finite? && depth >= 0
    end

    def spare_tire?(installed)
      position_name = installed["installedPositionName"].to_s.upcase

      installed["installedAxle"].to_i == SPARE_AXLE ||
        SPARE_POSITION_PREFIXES.any? { |prefix| position_name.start_with?(prefix) }
    end
  end
end
