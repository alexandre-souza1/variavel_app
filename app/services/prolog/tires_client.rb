require "httparty"

module Prolog
  class TiresClient
    include HTTParty

    BASE_URL = "https://prologapp.com/prolog/api/v3/tires".freeze
    DEFAULT_BRANCH_OFFICE_ID = 1834
    PAGE_SIZE = 100
    SPARE_AXLE = 9
    SPARE_POSITION_PREFIXES = %w[ETP ESTEPE SPARE].freeze

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
      return {} if @token.blank?

      page_number = 0
      depths = Hash.new { |hash, key| hash[key] = [] }

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
          next if spare_tire?(installed)

          plate = installed["licensePlate"]
          depth = tire["smallestTreadDepth"]
          next if plate.blank? || depth.blank?

          PlateUtils.equivalentes(plate).each do |equivalent_plate|
            depths[equivalent_plate] << depth.to_f
          end
        end

        break if payload["lastPage"] != false

        page_number += 1
        break if page_number >= 100
      end

      depths.transform_values { |values| values.min }
    rescue StandardError => e
      Rails.logger.warn("Não foi possível consultar as medidas de pneus no Prolog: #{e.message}")
      {}
    end

    private

    def spare_tire?(installed)
      position_name = installed["installedPositionName"].to_s.upcase

      installed["installedAxle"].to_i == SPARE_AXLE ||
        SPARE_POSITION_PREFIXES.any? { |prefix| position_name.start_with?(prefix) }
    end
  end
end
