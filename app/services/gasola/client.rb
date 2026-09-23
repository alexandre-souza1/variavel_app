require 'net/http'
require 'json'

module Gasola
  class Client
    class Error < StandardError; end

    def initialize(token: ENV['GASOLA_API_TOKEN'])
      @token = token
    end

    def supplies(from:, to:)
      raise Error, 'GASOLA_API_TOKEN não configurado.' if @token.blank?
      raise Error, 'Intervalo inválido para o Gasola.' unless to > from && to - from <= 30.days

      uri = URI('https://api.gasola.net/v1/integration/report/supply')
      uri.query = URI.encode_www_form(startDate: from.iso8601, endDate: to.iso8601)
      request = Net::HTTP::Get.new(uri)
      request['Authorization'] = @token
      request['Content-Type'] = 'application/json'
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 60) do |http|
        http.request(request)
      end
      raise Error, "Gasola respondeu HTTP #{response.code}." unless response.is_a?(Net::HTTPSuccess)

      data = JSON.parse(response.body)
      raise Error, 'Resposta inválida do Gasola.' unless data.is_a?(Array) && data.all? { |row| row.is_a?(Hash) }
      data
    rescue JSON::ParserError
      raise Error, 'Resposta inválida do Gasola.'
    rescue Timeout::Error, SocketError, SystemCallError, OpenSSL::SSL::SSLError, IOError
      raise Error, 'Falha de conexão com o Gasola.'
    end
  end
end
