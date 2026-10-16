require "test_helper"
require_relative "../support/automation_setup"

class AutomationRulesControllerTest < ActionDispatch::IntegrationTest
  include AutomationSetup
  setup { setup_automation_data; sign_in @owner }
  teardown { travel_back }

  test "index new edit and show render with configurable sources and actions" do
    get automation_rules_path
    assert_response :success
    assert_select "textarea#automation-description[required][maxlength='1800']"
    assert_select "button", text: "Gerar prévia com IA"
    assert_select "button[type=button][disabled][data-drawer-url=?]", new_automation_rule_path, text: "Nova automação"
    assert_select "a[href=?]", new_automation_rule_path, count: 0
    get new_automation_rule_path
    assert_response :success
    assert_select "select[name='automation_rule[source_key]'] option", count: 3
    assert_select "select[name='automation_rule[action_key]'] option", count: 3
    assert_select "select[multiple][name='automation_rule[filters][budget_category_ids][]']"
    rule = finance_rule.tap(&:save!)
    get edit_automation_rule_path(rule)
    assert_response :success
    get automation_rule_path(rule)
    assert_response :success
    get automation_rules_path(tab: "history")
    assert_response :success
    assert_select "textarea#automation-description", count: 0
  end

  test "drawer keeps preview and invalid submissions in its frame and returns a saved destination" do
    headers = { "Turbo-Frame" => "automation-form-drawer" }
    get new_automation_rule_path, headers: headers
    assert_response :success
    assert_select "turbo-frame#automation-form-drawer form[data-turbo='true']"
    assert_select ".dashboard-header", count: 0
    assert_no_difference "AutomationRule.count" do
      post automation_rules_path, params: { intent: "preview", automation_rule: attributes_for_rule }, headers: headers
      assert_response :success
      assert_select "turbo-frame#automation-form-drawer #automation-preview"
      post automation_rules_path, params: { automation_rule: attributes_for_rule.merge(name: "") }, headers: headers
      assert_response :unprocessable_entity
      assert_select "turbo-frame#automation-form-drawer [role='alert']"
    end
    assert_difference "AutomationRule.count", 1 do
      post automation_rules_path, params: { automation_rule: attributes_for_rule }, headers: headers
      assert_response :success
      assert_select "turbo-frame#automation-form-drawer [data-automation-saved-url=?]", automation_rules_path
    end
    rule = AutomationRule.last
    patch automation_rule_path(rule), params: { automation_rule: attributes_for_rule.merge(name: "Editada no painel") }, headers: headers
    assert_response :success
    assert_select "[data-automation-saved-url=?]", automation_rule_path(rule)
    assert_equal "Editada no painel", rule.reload.name
    assert_not rule.enabled?
  end

  test "preview never saves a rule or performs its action" do
    assert_no_difference ["AutomationRule.count", "RoutineValue.count", "AutomationRun.count", "Notification.count", "Task.count"] do
      post automation_rules_path, params: { intent: "preview", automation_rule: attributes_for_rule }
      assert_response :success
      assert_select "#automation-preview"
    end
  end

  test "creation forces current user ownership and paused status" do
    post automation_rules_path, params: { automation_rule: attributes_for_rule.merge(user_id: users(:two).id, enabled: true) }
    rule = AutomationRule.last
    assert_redirected_to automation_rule_path(rule)
    assert_equal @owner, rule.user
    assert_not rule.enabled?
    patch toggle_automation_rule_path(rule)
    assert rule.reload.enabled?
    patch automation_rule_path(rule), params: { automation_rule: attributes_for_rule.merge(name: "Alterada") }
    assert_equal "Alterada", rule.reload.name
    assert_not rule.enabled?
  end

  test "editing preview leaves enabled persisted configuration unchanged" do
    rule = finance_rule(enabled: true).tap(&:save!)
    patch automation_rule_path(rule), params: { intent: "preview", automation_rule: attributes_for_rule.merge(name: "Prévia") }
    assert_response :success
    assert rule.reload.enabled?
    assert_equal "Despesas no GEROT", rule.name
  end

  test "foreign rules are hidden and administrators can inspect them" do
    rule = finance_rule.tap(&:save!)
    sign_out @owner
    sign_in users(:two)
    get automation_rule_path(rule)
    assert_response :not_found
    sign_in users(:two)
    post execute_automation_rule_path(rule)
    assert_response :not_found
    users(:two).update!(role: :admin)
    sign_in users(:two)
    get automation_rule_path(rule)
    assert_response :success
  end

  test "mechanics and unauthenticated visitors cannot reach the module" do
    sign_out @owner
    get automation_rules_path
    assert_redirected_to new_user_session_path
    @owner.update!(role: :mechanical)
    sign_in @owner
    get automation_rules_path
    assert_redirected_to root_path
  end

  test "manual execution records outcome and manual GEROT edits clear automation ownership" do
    rule = finance_rule.tap(&:save!)
    create_automation_expense(100)
    post execute_automation_rule_path(rule)
    assert_redirected_to automation_rule_path(rule)
    target = @routine.routine_values.first
    assert_equal rule.id, target.automation_rule_id
    patch routine_value_path(target), params: { routine_value: { value: "125" } }, as: :json
    assert_response :success
    assert_nil target.reload.automation_rule_id
    assert_equal "125", target.value
    post execute_automation_rule_path(rule)
    assert_equal "125", target.reload.value
    assert_equal "skipped", rule.automation_runs.last.status
  end

  test "pausing remains possible after the owner loses source permissions" do
    rule = finance_rule(enabled: true).tap(&:save!)
    @owner.update!(sector: :hr)
    patch toggle_automation_rule_path(rule)
    assert_redirected_to automation_rule_path(rule)
    assert_not rule.reload.enabled?
    assert_nil rule.next_run_at
  end

  test "the form saves multiple categories and retains the selection when editing" do
    second = BudgetCategory.create!(name: "Manutenção empilhadeiras", sector: :frota)
    attributes = attributes_for_rule.merge("filters" => { "budget_category_ids" => ["", second.id.to_s, @category.id.to_s, second.id.to_s] })
    post automation_rules_path, params: { automation_rule: attributes }
    rule = AutomationRule.last
    assert_redirected_to automation_rule_path(rule)
    assert_equal [@category.id, second.id].sort.map(&:to_s), rule.filters["budget_category_ids"]
    get edit_automation_rule_path(rule)
    assert_response :success
    assert_select "#automation-categories option[value=\'#{@category.id}\'][selected]"
    assert_select "#automation-categories option[value=\'#{second.id}\'][selected]"
    patch automation_rule_path(rule), params: { automation_rule: attributes.merge("filters" => { "budget_category_ids" => [""] }) }
    assert_redirected_to automation_rule_path(rule)
    assert_empty rule.reload.filters["budget_category_ids"]
  end

  test "legacy single category is selected in the new picker and malformed lists cannot become all categories" do
    rule = finance_rule.tap(&:save!)
    get edit_automation_rule_path(rule)
    assert_response :success
    assert_select "#automation-categories option[value=\'#{@category.id}\'][selected]"
    assert_no_difference "AutomationRule.count" do
      post automation_rules_path, params: { automation_rule: attributes_for_rule.merge("filters" => { "budget_category_ids" => @category.id.to_s }) }
      assert_response :bad_request
    end
  end

  private

  def attributes_for_rule
    finance_rule.attributes.slice("name", "source_key", "operation", "period", "filters", "action_key", "action_config", "schedule")
  end
end
