require "test_helper"
require "minitest/mock"

class TireModuleControllerTest < ActionDispatch::IntegrationTest
  test "old overview redirects and page shells do not wait for any Prolog request" do
    Prolog::InspectionsClient.stub :new, ->(**) { flunk "A navegação não deve consultar a Prolog" } do
      get tire_dashboard_path
      assert_response :see_other
      assert_redirected_to tire_schedule_path
      [tire_schedule_path, tire_pressure_path, tire_inspections_path].each do |path|
        get path
        assert_response :success
        assert_select "turbo-frame#tire-report[data-tire-report-url-value=?]", path
        assert_select ".tire-loading"
        assert_select ".tire-view-tabs", count: 0
        assert_select "a[href=?]", dashboard_path
        assert_select ".tire-module-card", count: 0
      end
    end
  end

  test "every module page requires authentication" do
    sign_out :user
    [tire_dashboard_path, tire_schedule_path, tire_pressure_path, tire_inspections_path].each do |path|
      get path
      assert_redirected_to new_user_session_path
    end
  end

  test "DU users return home instead of receiving a link to the restricted fleet dashboard" do
    users(:one).update!(role: :user, sector: :du)
    get tire_schedule_path
    assert_response :success
    assert_select ".header-actions a[href=?]", variaveis_path
    assert_select ".header-actions a[href=?]", dashboard_path, count: 0
  end

  test "old overview preserves filters and CSV while redirecting to inspections" do
    get tire_dashboard_path, params: { q: "ABC", status: "overdue" }
    assert_redirected_to tire_schedule_path(q: "ABC", status: "overdue")
    get tire_dashboard_path(format: :csv), params: { status: "today" }
    assert_redirected_to tire_schedule_path(format: :csv, status: "today")
  end

  test "legacy view links redirect to dedicated pages preserving filters and CSV" do
    get tire_inspections_path, params: { view: "schedule", status: "overdue", q: "ABC" }
    assert_redirected_to tire_schedule_path(status: "overdue", q: "ABC")
    get tire_inspections_path(format: :csv), params: { view: "pressure", status: "persisted" }
    assert_redirected_to tire_pressure_path(format: :csv, status: "persisted")
  end

  test "deferred integration failure returns a matching frame with a retry action" do
    client = Object.new
    client.define_singleton_method(:fetch) { |**| raise Prolog::InspectionsClient::Error, "Falha na Prolog" }
    Prolog::InspectionsClient.stub :new, client do
      get tire_pressure_path, headers: { "Turbo-Frame" => "tire-report" }
      assert_response :service_unavailable
      assert_select "turbo-frame#tire-report"
      assert_select "[role=alert]", text: /Falha na Prolog/
      assert_select "a.btn-outline", text: "Tentar novamente"
      assert_select "tbody", count: 0
    end
  end

  test "pressure and divergences reuse the same successful history when filtering and paginating" do
    calls = 0
    client = Object.new
    client.define_singleton_method(:fetch) { |**| calls += 1; [] }
    Rails.stub :cache, ActiveSupport::Cache::MemoryStore.new do
      Prolog::InspectionsClient.stub :new, client do
        [tire_inspections_path, tire_pressure_path, tire_inspections_path(q: "ABC", page: 2)].each do |path|
          get path, headers: { "Turbo-Frame" => "tire-report" }
          assert_response :success
          assert_select "turbo-frame#tire-report"
        end
      end
    end
    assert_equal 1, calls
  end
end
