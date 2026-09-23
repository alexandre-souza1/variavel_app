require 'test_helper'
require 'minitest/mock'

class GasolaClientTest < ActiveSupport::TestCase
  def request_with(response)
    http = Object.new
    captured = []
    http.define_singleton_method(:request) { |request| captured << request; response }
    transport = ->(*_args, **_options, &block) { block.call(http) }
    Net::HTTP.stub(:start, transport) { yield captured }
  end

  def response(code, body)
    klass = code == '200' ? Net::HTTPOK : Net::HTTPUnauthorized
    result = klass.new('1.1', code, '')
    result.define_singleton_method(:body) { body }
    result
  end

  test 'uses raw authorization token and encoded datetime filters' do
    request_with(response('200', '[]')) do |requests|
      from = Time.zone.local(2026, 9, 1)
      assert_equal [], Gasola::Client.new(token: 'test-token').supplies(from: from, to: from + 1.day)
      assert_equal 'test-token', requests.first['Authorization']
      query = URI.decode_www_form(URI(requests.first.path).query).to_h
      assert_equal from.iso8601, query['startDate']
    end
  end

  test 'HTTP error does not expose body or credentials' do
    request_with(response('401', 'sensitive-response')) do
      error = assert_raises(Gasola::Client::Error) do
        Gasola::Client.new(token: 'test-secret').supplies(from: 1.day.ago, to: Time.current)
      end
      assert_equal 'Gasola respondeu HTTP 401.', error.message
    end
  end

  test 'invalid response is rejected rather than treated as empty data' do
    request_with(response('200', '{"error":"failed"}')) do
      assert_raises(Gasola::Client::Error) { Gasola::Client.new(token: 'test-token').supplies(from: 1.day.ago, to: Time.current) }
    end
  end
end
