require "minitest/autorun"
require "active_support/all"
require_relative "../../../app/services/prolog/inspections_client"

class PrologInspectionsClientTest < Minitest::Test
  Response = Struct.new(:code, :parsed_response) do
    def success? = code == 200
  end

  def test_fetches_both_sources_all_pages_and_required_filters
    requests = []
    responses = [Response.new(200, { "content" => [{ "id" => 1 }], "lastPage" => false }), Response.new(200, { "content" => [{ "id" => 2 }], "lastPage" => true }), Response.new(200, { "content" => [], "lastPage" => true })]
    http = Object.new
    http.define_singleton_method(:get) { |url, **options| requests << [url, options]; responses.shift }
    client = Prolog::InspectionsClient.new(token: "test", branch_office_id: 123, http_client: http)
    rows = client.fetch(start_time: Time.utc(2026, 6, 24), end_time: Time.utc(2026, 9, 24))
    assert_equal [1, 2], rows.map { |r| r["id"] }
    assert_equal [0, 1, 0], requests.map { |r| r.last[:query][:pageNumber] }
    assert requests.last.first.end_with?("/individual-tire")
    assert_equal "2026-06-24T00:00Z", requests.first.last[:query][:startDate]
    assert_equal true, requests.first.last[:query][:includeMeasures]
  end

  def test_failure_on_later_page_does_not_return_partial_report
    responses = [Response.new(200, { "content" => [{ "id" => 1 }], "lastPage" => false }), Response.new(401, {})]
    http = Object.new
    http.define_singleton_method(:get) { |*args, **options| responses.shift }
    client = Prolog::InspectionsClient.new(token: "test", branch_office_id: 123, http_client: http)
    assert_raises(Prolog::InspectionsClient::Error) { client.fetch(start_time: Time.now, end_time: Time.now) }
  end

  def test_missing_token_is_explicit_error
    client = Prolog::InspectionsClient.new(token: nil, branch_office_id: 123)
    assert_raises(Prolog::InspectionsClient::Error) { client.fetch(start_time: Time.now, end_time: Time.now) }
  end
end
