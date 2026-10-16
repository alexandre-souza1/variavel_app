require "test_helper"
require_relative "../support/automation_setup"

class AiAssistantAutomationsTest < ActiveSupport::TestCase
  include AutomationSetup
  setup do
    setup_automation_data
    @conversation = AiConversation.create!(user: @owner, request_token: "guide-1", requested_at: Time.current)
    @tools = AiAssistant::Tools.new(@owner, conversation: @conversation, request_token: "guide-1")
  end
  teardown { travel_back }

  test "catalog and lookups expose actual authorized connectors templates and indicators" do
    catalog = @tools.call("automation_options", {})
    assert_equal %w[invoices tasks fleet], catalog[:sources].pluck(:key)
    assert_equal %w[update_indicator create_task notify], catalog[:actions].pluck(:key)
    categories = @tools.call("automation_options", { group: "categories", query: "Abastecimento" })
    assert_equal [@category.id], categories[:records].pluck(:id)
    assert_equal [@template.id], @tools.call("automation_options", { group: "templates", query: "Automação teste" })[:records].pluck(:id)
    indicators = @tools.call("automation_options", { group: "indicators", template_id: @template.id })
    assert_equal [@indicator.id], indicators[:records].pluck(:id)
    assert_equal "monthly", indicators[:records].first[:frequency]
    assert_equal "currency", indicators[:records].first[:value_type]
    @owner.update!(sector: :warehouse)
    names = @tools.call("automation_options", {})[:sources].pluck(:key)
    assert_equal ["tasks"], names
    assert @tools.call("automation_options", { group: "categories" })[:error]
    assert @tools.call("automation_options", { group: "indicators", template_id: @template.id })[:error]
  end

  test "mechanics cannot access automation tools even by direct call" do
    @owner.update!(role: :mechanical)
    assert_empty @tools.declarations.pluck(:name) & AiAssistant::AutomationTools::FUNCTIONS
    AiAssistant::AutomationTools::FUNCTIONS.each { |name| assert @tools.call(name, {})[:error] }
    @owner.update!(role: :user, active: false)
    assert @tools.call("automation_options", {})[:error]
  end

  test "wizard preserves partial choices across messages and asks only the next required step" do
    state = @tools.call("configure_automation", { reset: true })
    assert_equal "source_key", state[:missing_fields].first
    refute state[:ready]
    partial = configuration.except("execution_hour")
    state = @tools.call("configure_automation", { configuration: partial })
    assert_equal ["execution_hour"], state[:missing_fields]
    assert_match(/horário/, state[:next_question])
    @conversation.finish!("guide-1", answer: { content: "Em qual horário?", sources: [] })
    @conversation.update!(request_token: "guide-2", requested_at: Time.current)
    tools = AiAssistant::Tools.new(@owner, conversation: @conversation, request_token: "guide-2")
    assert_equal "month", tools.automation_setup_context[:configuration]["period"]
    state = tools.call("configure_automation", { configuration: { execution_hour: 8 } })
    assert state[:ready]
    assert_equal "sum", state[:configuration]["operation"]
    assert_equal [@category.id.to_s], state[:configuration].dig("filters", "budget_category_ids")
    assert tools.call("prepare_automation", {})[:confirmation_required]
    assert_equal "create_automation", tools.drafts.sole[:kind]
  end

  test "preparation returns a stable explicit preview and read-only simulation without business writes" do
    create_automation_expense(123)
    result = nil
    assert_no_difference ["AutomationRule.count", "AutomationRun.count", "RoutineValue.count", "Task.count", "Notification.count", "Bucket.count", "AiActionRequest.count"] do
      result = @tools.call("prepare_automation", { configuration: configuration })
    end
    assert result[:confirmation_required]
    assert_equal false, result[:executed]
    assert_equal "123.0", result[:simulation][:value]
    assert_equal "Salvar automação pausada", result[:preview]["confirmation_label"]
    refute_includes result.to_json, "confirmation_token"
    @tools.call("prepare_automation", { configuration: configuration })
    assert_equal 1, @tools.drafts.size
    create_automation_expense(20)
    restored = AiAssistant::ActionDraft.restore(user: @owner, kind: "create_automation", payload: @tools.drafts.sole[:payload])
    assert_equal result[:preview], restored.preview
  end

  test "missing fields unsupported code actor overrides and invalid dates never become proposals" do
    [configuration.except("execution_hour"), configuration.merge("user_id" => users(:two).id),
     configuration.merge("source_key" => "sql"), configuration.merge("execution_hour" => 8.5),
     configuration.merge("activate" => "true"), configuration.merge("period" => "today"),
     configuration.merge("filters" => { "url" => "https://example.com" }),
     configuration.merge("action_config" => { "routine_template_id" => @template.id, "routine_indicator_id" => @indicator.id, "overwrite_manual" => "false" })].each do |config|
      assert @tools.call("prepare_automation", { configuration: config })[:error], config.inspect
    end
    assert_empty @tools.drafts
  end

  test "closed GEROT does not prevent staging a valid rule and simulation explains why it cannot run" do
    @routine.closed!
    result = @tools.call("prepare_automation", { configuration: configuration })
    assert result[:confirmation_required]
    assert_equal false, result[:simulation][:available]
    assert_match(/Nenhum GEROT aberto/, result[:simulation][:reason])
  end

  test "configuration and saved pending drafts stay private across users" do
    @tools.call("configure_automation", { configuration: configuration })
    other_conversation = AiConversation.create!(user: users(:two), request_token: "other")
    foreign = AiAssistant::Tools.new(users(:two), conversation: @conversation, request_token: "guide-1")
    assert foreign.call("configure_automation", {})[:error]
    assert foreign.call("prepare_automation", {})[:error]
    own = AiAssistant::Tools.new(users(:two), conversation: other_conversation, request_token: "other")
    assert_empty own.automation_setup_context
    assert_equal configuration["name"], @conversation.reload.automation_setup.dig("configuration", "name")
  end

  test "clearing permission changes expiry and replaced request tokens prevent stale wizard writes" do
    @tools.call("configure_automation", { configuration: configuration })
    @conversation.clear!
    assert_empty @conversation.reload.automation_setup
    assert @tools.call("configure_automation", { configuration: { execution_hour: 9 } })[:error]
    @conversation.update!(request_token: "guide-1")
    @tools.call("configure_automation", { configuration: configuration })
    @owner.update!(sector: :hr)
    assert @tools.automation_setup_context[:expired]
    assert_empty @conversation.reload.automation_setup
    @owner.update!(sector: :fleet)
    @tools.call("configure_automation", { configuration: configuration })
    travel 3.hours
    assert @tools.automation_setup_context[:expired]
    assert_empty @conversation.reload.automation_setup
  end

  test "changing connectors clears incompatible choices and keeps independent selections" do
    @tools.call("configure_automation", { configuration: configuration })
    state = @tools.call("configure_automation", { configuration: { source_key: "fleet" } })
    assert_nil state[:configuration]["period"]
    assert_equal "count", state[:configuration]["operation"]
    assert_nil state[:configuration]["filters"]
    assert_equal "daily", state[:configuration]["schedule"]
  end

  test "wizard data is not required when the full configuration is already explicit" do
    tools = AiAssistant::Tools.new(@owner)
    result = tools.call("prepare_automation", { configuration: configuration.merge("activate" => true) })
    assert result[:confirmation_required]
    assert_equal "Salvar e ativar automação", result[:preview]["confirmation_label"]
    assert_equal true, tools.drafts.sole[:payload]["activate"]
  end

  test "task and notification rules reuse the generic engine and scope bucket destinations" do
    config = { name: "Avisar pendências", source_key: "tasks", period: "today", filters: { status: "overdue" },
      condition_operator: "gt", condition_value: 3, action_key: "notify", action_config: { title: "Revisar {{valor}} tarefas" }, schedule: "hourly" }
    result = @tools.call("prepare_automation", { configuration: config })
    assert result[:confirmation_required]
    assert_equal "count", @tools.drafts.sole[:payload]["operation"]
    other = users(:two).action_plans.create!(name: "Plano RH privado", sector: :hr, public: false)
    config.merge!(action_key: "create_task", action_config: { title: "Revisar", bucket_id: other.buckets.first.id })
    assert @tools.call("prepare_automation", { configuration: config })[:error]
  end

  test "AI packages several categories in one draft and renders all category names" do
    forklift = BudgetCategory.create!(name: "Manutenção empilhadeiras", sector: :frota)
    create_automation_expense(100)
    create_automation_expense(200, category: forklift)
    config = configuration.merge("filters" => { "budget_category_ids" => [@category.id, forklift.id, @category.id] })
    result = @tools.call("prepare_automation", { configuration: config })
    assert result[:confirmation_required]
    assert_equal "300.0", result[:simulation][:value]
    draft = @tools.drafts.sole
    assert_equal [@category.id, forklift.id].sort.map(&:to_s), draft[:payload].dig("filters", "budget_category_ids")
    summary = result[:preview]["details"].find { |item| item["label"] == "Filtros" }["value"]
    assert_includes summary, @category.name
    assert_includes summary, forklift.name
    config["filters"]["budget_category_ids"] = [forklift.id, @category.id]
    @tools.call("prepare_automation", { configuration: config })
    assert_equal 1, @tools.drafts.size
  end

  test "guided category edits replace the full list and adapt legacy state without losing other fields" do
    forklift = BudgetCategory.create!(name: "Manutenção empilhadeiras", sector: :frota)
    @conversation.update!(automation_setup: { configuration: configuration, access: { role: @owner.role, sector: @owner.sector }, expires_at: 2.hours.from_now.iso8601 })
    result = @tools.call("configure_automation", { configuration: { filters: { budget_category_ids: [@category.id, forklift.id] } } })
    assert result[:ready]
    assert_equal 2, result[:configuration].dig("filters", "budget_category_ids").size
    assert_equal 8, result[:configuration]["execution_hour"]
    result = @tools.call("configure_automation", { configuration: { filters: { budget_category_ids: [forklift.id] } } })
    assert result[:ready]
    assert_equal [forklift.id.to_s], result[:configuration].dig("filters", "budget_category_ids")
    refute result[:configuration]["filters"].key?("budget_category_id")
  end

  test "AI rejects the full proposal if even one category is unauthorized or the list is malformed" do
    hr = BudgetCategory.create!(name: "Categoria privada RH", sector: :rh)
    [@category.id, [@category.id, hr.id], [@category.id, 1.5]].each do |ids|
      assert @tools.call("prepare_automation", { configuration: configuration.merge("filters" => { "budget_category_ids" => ids }) })[:error]
    end
    assert_empty @tools.drafts
    assert @tools.call("prepare_automation", { configuration: configuration })[:confirmation_required]
    assert_equal [@category.id.to_s], @tools.drafts.sole[:payload].dig("filters", "budget_category_ids")
  end

  private

  def configuration
    { "name" => "Combustível no GEROT", "source_key" => "invoices", "operation" => "sum", "period" => "month",
      "filters" => { "budget_category_id" => @category.id }, "action_key" => "update_indicator",
      "action_config" => { "routine_template_id" => @template.id, "routine_indicator_id" => @indicator.id },
      "schedule" => "daily", "execution_hour" => 8 }
  end
end
