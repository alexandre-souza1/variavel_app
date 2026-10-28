require "test_helper"

class Prolog::CachedInspectionsTest < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
    @calls = []
    calls = @calls
    @client = Object.new
    @client.define_singleton_method(:fetch) { |**options| calls << options; [{ "id" => calls.size }] }
    @client.define_singleton_method(:tread_inspections) { calls << :tread; [{ "id" => calls.size }] }
  end

  test "reuses complete histories for five minutes and isolates periods and credentials" do
    travel_to Time.zone.local(2026, 10, 27, 12) do
      scope = { start_time: 3.months.ago.beginning_of_day, end_time: Time.current.end_of_day }
      cached = source
      first = cached.fetch(**scope)
      assert_equal first, source.fetch(**scope)
      assert_equal 1, @calls.size
      cached.fetch(**scope.merge(start_time: 2.months.ago.beginning_of_day))
      source(token: "another-token").fetch(**scope)
      source(branch_office_id: 456).fetch(**scope)
      assert_equal 4, @calls.size
      travel 6.minutes
      cached.fetch(**scope)
      assert_equal 5, @calls.size
    end
  end

  test "tread metadata has its own ten minute cache and errors can be retried immediately" do
    travel_to Time.zone.local(2026, 10, 27, 12) do
      first = source.tread_inspections
      assert_equal first, source.tread_inspections
      assert_equal 1, @calls.size
      travel 11.minutes
      source.tread_inspections
      assert_equal 2, @calls.size
    end
    failing = Object.new
    failing.define_singleton_method(:fetch) { |**| raise Prolog::InspectionsClient::Error, "Falha" }
    scope = { start_time: 1.day.ago, end_time: Time.current }
    assert_raises(Prolog::InspectionsClient::Error) { source(client: failing).fetch(**scope) }
    assert_equal [{ "id" => 3 }], source.fetch(**scope)
  end

  private

  def source(**options)
    Prolog::CachedInspections.new(client: @client, cache: @cache, token: "test", branch_office_id: 123, **options)
  end
end
