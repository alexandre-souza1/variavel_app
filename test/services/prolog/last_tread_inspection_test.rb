require "test_helper"
require "minitest/mock"

class Prolog::LastTreadInspectionTest < ActiveSupport::TestCase
  Response = Struct.new(:code, :parsed_response) do
    def success? = code == 200
  end

  setup do
    travel_to Time.zone.local(2026, 10, 27, 12)
    @responses = []
    @requests = []
    responses, requests = @responses, @requests
    http = Object.new
    http.define_singleton_method(:get) do |url, **options|
      requests << [url, options]
      responses.shift || raise("Unexpected request")
    end
    @client = Prolog::InspectionsClient.new(token: "test", branch_office_id: 123, http_client: http)
    @cache = ActiveSupport::Cache::MemoryStore.new
  end

  teardown { travel_back }

  test "finds the latest tread inspection across pages and equivalent plates ignoring pressure only records" do
    @responses.concat([
      page([inspection("2024-01-01T12:00:00Z"), inspection("2026-10-26T12:00:00Z", type: "PRESSURE")], last: false),
      page([inspection("2026-10-19T20:28:00Z", plate: " abc-1323 "),
            inspection("2026-10-26T12:00:00Z", plate: "DEF4G56"),
            inspection("invalid"), inspection("2026-10-28T12:00:00Z")]),
      page([inspection("2026-10-15T12:00:00Z", type: "TREAD_DEPTH")])
    ])

    result = last_inspection

    assert_equal Time.iso8601("2026-10-19T20:28:00Z"), result
    assert_equal [0, 1, 0], @requests.map { |_, options| options[:query][:pageNumber] }
    assert_equal %w[ABC1D23 ABC1D23 ABC1323], @requests.map { |_, options| options[:query][:textQuery] }
    @requests.each do |url, options|
      assert url.end_with?("/vehicles")
      assert_equal false, options[:query][:includeMeasures]
      assert_equal "1970-01-01T00:00Z", options[:query][:startDate]
      assert_equal 123, options[:query][:branchOfficesId]
    end
  end

  test "returns older inspections and caches the date for ten minutes" do
    @responses.concat([page([inspection("2024-01-01T12:00:00Z")]), page([])])
    assert_equal Time.iso8601("2024-01-01T12:00:00Z"), last_inspection
    assert_equal Time.iso8601("2024-01-01T12:00:00Z"), last_inspection
    assert_equal 2, @requests.size

    travel 11.minutes
    @responses.concat([page([inspection("2026-10-27T14:00:00Z")]), page([])])
    assert_equal Time.iso8601("2026-10-27T14:00:00Z"), last_inspection
    assert_equal 4, @requests.size
  end

  test "does not use a partial history or cache failed requests" do
    @responses.concat([page([inspection("2026-10-01T12:00:00Z")], last: false), Response.new(503, {})])
    assert_raises(Prolog::InspectionsClient::Error) { last_inspection }

    @responses.concat([page([inspection("2026-10-20T12:00:00Z")]), page([])])
    assert_equal Time.iso8601("2026-10-20T12:00:00Z"), last_inspection
  end

  test "distinguishes no tread inspection from an unavailable integration" do
    @responses.concat([page([inspection("2026-10-26T12:00:00Z", type: "PRESSURE")]), page([])])
    assert_nil last_inspection

    client = Prolog::InspectionsClient.new(token: nil)
    assert_raises(Prolog::InspectionsClient::Error) { client.last_tread_inspection_at("ABC1D23") }
  end

  test "fleet history fetches vehicle pages once and shares the cache across plates" do
    @responses.concat([page([inspection("2024-01-01T12:00:00Z")], last: false), page([inspection("2026-10-20T12:00:00Z", plate: "DEF4G56")])])
    cached = Prolog::CachedInspections.new(client: @client, cache: @cache)
    Rails.stub :cache, @cache do
      assert_equal 2, cached.tread_inspections.size
      assert_equal 2, cached.tread_inspections.size
      assert_equal 2, @requests.size
      assert_equal [0, 1], @requests.map { |_, options| options[:query][:pageNumber] }
      @requests.each do |url, options|
        assert url.end_with?("/vehicles")
        assert_equal false, options[:query][:includeMeasures]
        assert_equal "1970-01-01T00:00Z", options[:query][:startDate]
        refute options[:query].key?(:textQuery)
      end
      travel 11.minutes
      @responses << page([])
      assert_empty cached.tread_inspections
    end
  end

  test "fleet history never caches partial pages or failed responses" do
    @responses.concat([page([inspection("2026-10-01T12:00:00Z")], last: false), Response.new(503, {})])
    cached = Prolog::CachedInspections.new(client: @client, cache: @cache)
    Rails.stub :cache, @cache do
      assert_raises(Prolog::InspectionsClient::Error) { cached.tread_inspections }
      @responses << page([])
      assert_empty cached.tread_inspections
    end
  end

  private

  def page(records, last: true)
    Response.new(200, { "content" => records, "lastPage" => last })
  end

  def inspection(date, plate: "ABC1D23", type: "TREAD_DEPTH_PRESSURE")
    { "submittedAt" => date, "typeMeasurementsCollected" => type, "vehicle" => { "licensePlate" => plate } }
  end

  def last_inspection
    Rails.stub(:cache, @cache) { @client.last_tread_inspection_at("ABC1D23") }
  end
end
