require "test_helper"

class AiAssistantToolsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @user.update!(role: :user, sector: :fleet)
    @private_plan = users(:two).action_plans.create!(name: "Plano confidencial", sector: :warehouse, public: false)
    @private_task = Task.create!(title: "Pendência confidencial", bucket: @private_plan.buckets.first, creator: users(:two))
    @tools = AiAssistant::Tools.new(@user)
  end

  test "private plans tasks and inboxes do not leak through searches or direct identifiers" do
    other_inbox = users(:two).personal_inbox!
    Task.create!(title: "Entrada confidencial", bucket: other_inbox, creator: users(:two))
    assert_equal 0, @tools.call("list_plans", { query: "confidencial" })[:total]
    assert_equal 0, @tools.call("list_tasks", { query: "confidencial" })[:total]
    assert @tools.call("summarize_plan", { plan_id: @private_plan.id })[:error]
    assert @tools.call("list_tasks", { plan_id: @private_plan.id })[:error]
    assert_empty @tools.sources
  end

  test "assigned tasks and shared plans are available without exposing another inbox" do
    @private_task.users << @user
    own = Task.create!(title: "Entrada própria", creator: @user, bucket: @user.personal_inbox!)
    result = @tools.call("list_tasks", { status: "all" })
    ids = result[:records].map { |task| task[:id] }
    assert_includes ids, @private_task.id
    assert_includes ids, own.id
    assert_equal 1, @tools.call("list_plans", { query: "confidencial" })[:total]
  end

  test "mechanics see only assigned tasks and their own inbox in summaries" do
    @user.update!(role: :mechanical)
    @private_task.users << @user
    Task.create!(title: "Tarefa de outro mecânico", bucket: @private_plan.buckets.first, creator: users(:two))
    assert_equal [@private_task.id], @tools.call("list_tasks", { plan_id: @private_plan.id })[:records].map { |task| task[:id] }
    assert_equal 1, @tools.call("summarize_plan", { plan_id: @private_plan.id })[:visible_tasks]
    assert @tools.call("fleet_status", {})[:error]
  end

  test "task totals do not duplicate assignees and overdue excludes completed tasks" do
    @private_task.users << @user
    @private_task.users << users(:two)
    @private_task.update_columns(due_at: 2.days.ago, completed: false)
    completed = Task.create!(title: "Concluída atrasada", bucket: @private_plan.buckets.first, creator: @user, due_at: 2.days.ago, completed: true)
    completed.users << @user
    summary = @tools.call("summarize_plan", { plan_id: @private_plan.id })
    assert_equal 2, summary[:visible_tasks]
    assert_equal 1, summary[:overdue_tasks]
    result = @tools.call("list_tasks", { plan_id: @private_plan.id, mine: true, status: "overdue" })
    assert_equal 1, result[:total]
    assert_equal [@private_task.id], result[:records].map { |task| task[:id] }
  end

  test "fleet respects the requested date sector restrictions and invalid filters" do
    assert_equal false, @tools.call("fleet_status", { date: "2040-01-02" })[:available]
    assert @tools.call("fleet_status", { date: "invalid" })[:error]
    @user.update!(sector: :finance)
    assert @tools.call("fleet_status", {})[:error]
    assert @tools.call("destroy_all", {})[:error]
    refute @tools.call("navigation", {})[:links].any? { |link| link[:label] == "Usuários e permissões" }
  end

  test "fleet returns real availability with reasons and excludes retired vehicles" do
    fleet = FleetAvailability.create!(user: @user, date: Date.current, agreed_quantity: 1)
    plates(:one).update_columns(placa: "TEST-1234")
    FleetAvailabilityItem.create!(fleet_availability: fleet, plate: plates(:one), status: :unavailable,
      reason: :maintenance, observation: "Freios em revisão", position: 1)
    plates(:two).update_columns(active: false, retired_at: Date.current)
    FleetAvailabilityItem.create!(fleet_availability: fleet, plate: plates(:two), status: :unavailable, position: 2)
    result = @tools.call("fleet_status", { date: Date.current.iso8601, status: "unavailable" })
    assert_equal 1, result[:total]
    assert_equal({ "unavailable" => 1 }, result[:counts])
    assert_equal "Manutenção", result[:records].first[:reason]
    assert_equal "TEST-1234", result[:records].first[:plate]
    assert_equal Rails.application.routes.url_helpers.fleet_availability_path(fleet), @tools.sources.last[:path]
  end

  test "pagination reports full totals and escapes wildcard searches" do
    21.times do |number|
      Task.create!(title: "Teste de página #{number}", bucket: @private_plan.buckets.first, creator: @user)
    end
    page_one = @tools.call("list_tasks", { query: "Teste de página" })
    page_two = @tools.call("list_tasks", { query: "Teste de página", page: 2 })
    assert_equal 21, page_one[:total]
    assert_equal 20, page_one[:records].size
    assert page_one[:has_more]
    assert_equal 1, page_two[:records].size
    refute page_two[:has_more]
    assert_equal 0, @tools.call("list_tasks", { query: "%" })[:total]
  end
end
