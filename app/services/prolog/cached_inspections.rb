require "digest"

module Prolog
  class CachedInspections
    # O desenvolvimento usa NullStore por padrão; o cache local evita repetir
    # as chamadas externas sem mudar a configuração dos outros módulos.
    LOCAL_CACHE = ActiveSupport::Cache::MemoryStore.new(size: 32.megabytes)

    def initialize(client: nil, cache: nil, token: ENV["PROLOG_API_TOKEN"], branch_office_id: ENV["PROLOG_BRANCH_OFFICE_ID"].presence || TiresClient::DEFAULT_BRANCH_OFFICE_ID)
      @client = client
      @token, @branch_office_id = token, branch_office_id
      @cache = cache || Rails.cache
      @cache = LOCAL_CACHE if cache.nil? && @cache.is_a?(ActiveSupport::Cache::NullStore) && !Rails.env.test?
      @scope = [@branch_office_id, Digest::SHA256.hexdigest(@token.to_s)]
    end

    def fetch(start_time:, end_time:)
      @cache.fetch(["prolog/inspection_history/v1", *@scope, start_time.to_i, end_time.to_i], expires_in: 5.minutes) do
        client.fetch(start_time: start_time, end_time: end_time)
      end
    end

    def tread_inspections
      @cache.fetch(["prolog/fleet_tread_history/v1", *@scope], expires_in: 10.minutes) { client.tread_inspections }
    end

    private

    def client
      @client ||= InspectionsClient.new(token: @token, branch_office_id: @branch_office_id)
    end
  end
end
