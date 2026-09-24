require "httparty"

module Prolog
  class InspectionsClient
    class Error < StandardError; end
    BASE_URL = "https://prologapp.com/prolog/api/v3/tire-inspections".freeze

    def initialize(token: ENV["PROLOG_API_TOKEN"], branch_office_id: ENV["PROLOG_BRANCH_OFFICE_ID"].presence || TiresClient::DEFAULT_BRANCH_OFFICE_ID, http_client: HTTParty)
      @token, @branch_office_id, @http = token, branch_office_id, http_client
    end

    def fetch(start_time:, end_time:)
      raise Error, "A integração com a Prolog não está configurada." if @token.blank?

      %w[vehicles individual-tire].flat_map do |source|
        rows = []
        page = 0
        loop do
          response = @http.get("#{BASE_URL}/#{source}", headers: { "x-prolog-api-token" => @token },
            query: { branchOfficesId: @branch_office_id, startDate: start_time.utc.strftime("%Y-%m-%dT%H:%MZ"),
                     endDate: end_time.utc.strftime("%Y-%m-%dT%H:%MZ"), includeMeasures: true, pageSize: 100, pageNumber: page }, timeout: 20)
          raise Error, "Não foi possível consultar as aferições na Prolog (HTTP #{response.code})." unless response.success?

          payload = response.parsed_response
          unless payload.is_a?(Hash) && payload["content"].is_a?(Array) && [true, false].include?(payload["lastPage"])
            raise Error, "A Prolog retornou uma resposta inesperada."
          end
          rows.concat(payload["content"].map { |row| row.merge("source" => source) })
          break if payload["lastPage"]
          page += 1
          raise Error, "A consulta excedeu o limite de páginas. Reduza o período." if page >= 100
        end
        rows
      end
    rescue Error
      raise
    rescue StandardError => e
      Rails.logger.warn("Prolog inspections: #{e.class}")
      raise Error, "Não foi possível consultar as aferições na Prolog. Tente novamente."
    end
  end
end
