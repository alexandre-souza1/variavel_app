require "test_helper"
require "minitest/mock"
require_relative "../support/automation_setup"

class AiAssistantAutomationsControllerTest < ActionDispatch::IntegrationTest
  include AutomationSetup
  setup do
    setup_automation_data
    sign_in @owner
    @conversation = AiConversation.create!(user: @owner)
  end
  teardown { travel_back }

  test "confirmation creates exactly one paused rule with no business action and durable audit" do
    request = proposal
    assert_no_difference ["RoutineValue.count", "AutomationRun.count", "Task.count", "Notification.count"] do
      assert_difference "AutomationRule.count", 1 do
        confirm(request)
        assert_response :success
      end
    end
    rule = AutomationRule.find(request.reload.result["id"])
    assert_not rule.enabled?
    assert_equal @owner.id, rule.user_id
    assert_equal "executed", request.status
    assert_equal false, request.result["enabled"]
    assert_empty @conversation.reload.automation_setup
    assert_no_difference "AutomationRule.count" do
      confirm(request)
      assert_response :success
    end
    assert_equal request.id, @owner.ai_action_requests.where(kind: "create_automation", status: "executed").sole.id
  end

  test "explicit activation schedules the rule but never runs it during confirmation" do
    request = proposal(activate: true)
    assert_no_difference ["AutomationRun.count", "RoutineValue.count", "Task.count", "Notification.count"] do
      confirm(request)
      assert_response :success
    end
    rule = AutomationRule.find(request.reload.result["id"])
    assert rule.enabled?
    assert rule.next_run_at > Time.current
  end

  test "tokens ownership expiration and text approval cannot create a rule" do
    request = proposal
    assert_no_difference "AutomationRule.count" do
      post confirm_ai_assistant_action_path(request), params: { approved: true }, as: :json
      assert_response :unprocessable_entity
      sign_out @owner
      sign_in users(:two)
      confirm(request)
      assert_response :not_found
      sign_in @owner
      travel 31.minutes
      confirm(request)
      assert_response :conflict
    end
  end

  test "confirmation rechecks access and rejects renamed or conflicting destinations" do
    request = proposal(activate: true)
    @indicator.update!(name: "Novo nome")
    confirm(request)
    assert_response :conflict
    assert_empty AutomationRule.all
    request = proposal(activate: true)
    finance_rule(enabled: true).save!
    confirm(request)
    assert_response :unprocessable_entity
    assert_equal 1, AutomationRule.count
    assert_equal "pending", request.reload.status
  end

  test "permission loss cancellation and clearing preserve records and invalidate drafts" do
    request = proposal
    @owner.update!(sector: :hr)
    confirm(request)
    assert_response :forbidden
    @owner.update!(sector: :fleet)
    post cancel_ai_assistant_action_path(request), as: :json
    assert_response :success
    confirm(request)
    assert_response :conflict
    request = proposal
    delete ai_assistant_path, as: :json
    assert_response :success
    confirm(request)
    assert_response :conflict
    assert_empty AutomationRule.all
  end

  test "adjusting produces a replacement draft without executing the previous version" do
    first = proposal
    replacement = proposal(hour: 9)
    assert_equal "cancelled", first.reload.status
    pending = AiAssistant::Tools.new(@owner).call("pending_actions", {})
    assert_equal 9, pending[:proposals].sole[:data]["execution_hour"]
    refute_includes pending.to_json, replacement.confirmation_token
    confirm(replacement)
    assert_response :success
    assert_equal 9, AutomationRule.sole.execution_hour
  end

  test "existing singular-category proposals still confirm with the same preview" do
    request = proposal
    old = request.payload.deep_dup
    old["filters"] = { "budget_category_id" => @category.id.to_s }
    AiActionRequest.where(id: request.id).update_all(payload: old)
    confirm(request.reload)
    assert_response :success
    assert_equal [@category.id.to_s], AutomationRule.sole.filters["budget_category_ids"]
  end

  test "confirmation saves every selected category in the same rule" do
    second = BudgetCategory.create!(name: "Manutenção empilhadeiras", sector: :frota)
    request = proposal
    @conversation.update!(request_token: "multiple", requested_at: Time.current)
    payload = request.payload.merge("filters" => { "budget_category_ids" => [@category.id, second.id] })
    draft = AiAssistant::ActionDraft.build(user: @owner, kind: "create_automation", arguments: payload)
    @conversation.finish!("multiple", answer: { content: "Confira o pacote.", sources: [], actions: [draft.to_h] })
    request = @conversation.ai_action_requests.order(:id).last
    assert_difference "AutomationRule.count", 1 do
      confirm(request)
      assert_response :success
    end
    assert_equal [@category.id, second.id].sort.map(&:to_s), AutomationRule.sole.filters["budget_category_ids"]
  end

  private

  def proposal(activate: false, hour: 8)
    draft = AiAssistant::ActionDraft.build(user: @owner, kind: "create_automation", arguments: {
      name: "Regra pela IA", source_key: "invoices", operation: "sum", period: "month",
      filters: { budget_category_id: @category.id }, action_key: "update_indicator",
      action_config: { routine_template_id: @template.id, routine_indicator_id: @indicator.id },
      schedule: "daily", execution_hour: hour, activate: activate
    })
    @conversation.update!(request_token: "draft", requested_at: Time.current)
    @conversation.finish!("draft", answer: { content: "Confira a regra antes de confirmar.", sources: [], actions: [draft.to_h] })
    @conversation.ai_action_requests.order(:id).last
  end

  def confirm(request)
    post confirm_ai_assistant_action_path(request), params: { confirmation_token: request.confirmation_token }, as: :json
  end
end
