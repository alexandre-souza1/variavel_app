require "test_helper"
require "minitest/mock"

class DashboardTireDivergencesTest < ActiveSupport::TestCase
  setup { travel_to Time.zone.local(2026, 9, 24, 12) }
  teardown { travel_back }

  test "dashboard shows ten newest increases from current month with previous month baseline" do
    records = (1..13).map do |id|
      { "id" => id, "source" => "vehicles", "submittedAt" => (Time.utc(2026, 8, 31, 12) + (id - 1).days).iso8601,
        "inspectionMeasures" => [{ "tireId" => 1, "tireSerialNumber" => "PNEU", "tireLifeCycleAtInspection" => 1, "measuredInnerTreadDepth" => id }] }
    end
    client = Object.new
    client.define_singleton_method(:fetch) { |**options| records }
    controller = DashboardsController.new
    Prolog::InspectionsClient.stub :new, client do
      controller.send(:load_tire_divergences)
    end
    assert_equal 12, controller.instance_variable_get(:@tire_divergence_count)
    rows = controller.instance_variable_get(:@tire_divergences)
    assert_equal 10, rows.size
    assert_equal 13, rows.first[:current][:record]["id"]
    assert_equal 4, rows.last[:current][:record]["id"]
    html = ApplicationController.render(partial: "dashboards/tire_divergences", assigns: controller.view_assigns)
    assert_includes html, "Ver todas do mês"
    assert_includes html, "12 aumentos de sulco no mês"
  end

  test "API failure stays inside the card" do
    client = Object.new
    client.define_singleton_method(:fetch) { |**options| raise Prolog::InspectionsClient::Error, "Falha Prolog" }
    controller = DashboardsController.new
    Prolog::InspectionsClient.stub :new, client do
      controller.send(:load_tire_divergences)
    end
    html = ApplicationController.render(partial: "dashboards/tire_divergences", assigns: controller.view_assigns)
    assert_includes html, "Não foi possível carregar o resumo"
    refute_includes html, "Nenhum aumento"
  end
end
